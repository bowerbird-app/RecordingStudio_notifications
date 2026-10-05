# frozen_string_literal: true

require "test_helper"

class RecordingStudioV3TemplateTest < ActiveSupport::TestCase
  test "dummy app loads root switchable config and controller support" do
    assert_equal [ "all_workspaces", "admin_root" ], RecordingStudioRootSwitchable.configuration.scopes.keys
    assert_equal :application_layout, RecordingStudioRootSwitchable.configuration.layout
    assert_includes ApplicationController.ancestors, RecordingStudio::RootSwitchable::ControllerSupport
  end

  test "dummy app validates v3 recordable declarations" do
    assert RecordingStudio.validate_recordable_declarations!
    assert_equal [ "Workspace", "AdminRoot" ], RecordingStudio.root_recordable_types
    assert_equal [ "Workspace", "Folder" ], RecordingStudio.allowed_parent_types_for("Page")
  end

  test "dummy app schema includes accessible integration tables" do
    connection = ActiveRecord::Base.connection
    role = connection.columns(:recording_studio_accesses).find { |column| column.name == "role" }

    assert connection.column_exists?(:recording_studio_recordings, :root_recording_id)
    assert connection.table_exists?(:recording_studio_accesses)
    assert connection.table_exists?(:recording_studio_access_invitations)
    assert connection.column_exists?(:recording_studio_accesses, :depends_on_recording_id)
    assert_equal :string, role.type
    refute connection.table_exists?(:recording_studio_access_boundaries)
    refute connection.table_exists?(:recording_studio_device_sessions)
  end

  test "Gemfiles pin Accessible to v0.11.1" do
    root_gemfile = File.read(Rails.root.join("../../Gemfile"))
    dummy_gemfile = File.read(Rails.root.join("Gemfile"))

    assert_match(/recording_studio_accessible.*, tag: "v0.11.1"/, root_gemfile)
    assert_match(/recording_studio_accessible.*, tag: "v0.11.1"/, dummy_gemfile)
  end

  test "dummy seeds use v3 hierarchy idempotently and restore current actor" do
    Current.actor = nil

    load Rails.root.join("db/seeds.rb").to_s

    workspace = Workspace.find_by!(name: "Studio Workspace")
    accessible_workspace = Workspace.find_by!(name: "Client Workspace")
    private_workspace = Workspace.find_by!(name: "Private Workspace")
    folder = Folder.find_by!(name: "Product Docs")
    page = Page.find_by!(title: "Getting Started")
    root_recording = RecordingStudio::Recording.find_by!(recordable: workspace)
    accessible_root_recording = RecordingStudio::Recording.find_by!(recordable: accessible_workspace)
    private_root_recording = RecordingStudio::Recording.find_by!(recordable: private_workspace)
    admin_root_recording = RecordingStudio::Recording.find_by!(recordable: AdminRoot.first!)
    folder_recording = RecordingStudio::Recording.find_by!(recordable: folder)
    page_recording = RecordingStudio::Recording.find_by!(recordable: page)

    assert_nil Current.actor
    assert_nil root_recording.parent_recording_id
    assert_nil accessible_root_recording.parent_recording_id
    assert_nil private_root_recording.parent_recording_id
    assert_equal root_recording, folder_recording.parent_recording
    assert_equal root_recording, folder_recording.root_recording
    assert_equal folder_recording, page_recording.parent_recording
    assert_equal root_recording, page_recording.root_recording
    assert_equal 3, Workspace.count

    admin = User.find_by!(email: "admin@admin.com")
    commenter = User.find_by!(email: "commenter@commenter.com")
    private_user = User.find_by!(email: "private@private.com")

    assert_equal "edit", RecordingStudioAccessible.role_for(actor: admin, recording: root_recording).to_s
    assert_equal "edit", RecordingStudioAccessible.role_for(actor: commenter, recording: root_recording).to_s
    assert_equal "edit", RecordingStudioAccessible.role_for(actor: admin, recording: accessible_root_recording).to_s
    assert_equal "admin", RecordingStudioAccessible.role_for(actor: admin, recording: admin_root_recording).to_s
    assert_equal "admin", RecordingStudioAccessible.role_for(actor: private_user, recording: private_root_recording).to_s
    assert(RecordingStudio::Access.distinct.pluck(:role).all? { |role| role.is_a?(String) })

    seeded = RecordingStudioNotifications::Notification.where(recipient: admin)
    types = seeded.distinct.pluck(:notification_type).sort

    assert_equal %w[approval_requested mention page_comment page_created system_announcement workspace_change], types
    assert seeded.unread.exists?
    assert seeded.where.not(read_at: nil).exists?
    refute seeded.where("title LIKE ?", "System announcement %").exists?

    assert_no_difference -> { User.count } do
      assert_no_difference -> { RecordingStudio::Recording.count } do
        load Rails.root.join("db/seeds.rb").to_s
      end
    end
    assert_nil Current.actor
  ensure
    Current.actor = nil
  end

end
