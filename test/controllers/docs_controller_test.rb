# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

require "devise/test/integration_helpers"
require "rails/test_help"

class DocsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TEST_PASSWORD = "DocsTestPassword!2026"

  setup do
    @user = User.find_or_create_by!(email: "docs-test@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user
  end

  test "install page renders successfully" do
    get docs_install_path
    assert_response :success
    assert_select "h1", text: "Install"
    assert_includes response.body, "1. Add the gem"
    assert_includes response.body, "recording_studio_notifications"
    assert_includes response.body, "bin/rails generate recording_studio_notifications:install"
    assert_includes response.body, "/recording_studio_notifications"
    assert_includes response.body, "--mount-path=/notifications"
    assert_includes response.body, "bin/rails tailwindcss:build"
    assert_includes response.body, "bin/rails generate recording_studio_notifications:migrations"
  end

  test "config page renders successfully" do
    get docs_config_path
    assert_response :success
    assert_select "h1", text: "Configuration & Usage"
    assert_includes response.body, "config.polling_interval_seconds = 60"
    assert_includes response.body, "polling_interval_seconds"
    assert_includes response.body, "Polling cadence in seconds for async notification menu refresh"
    assert_includes response.body, "Per-Recipient Channel Preferences"
    assert_includes response.body, "Notification Cadences &amp; Digests"
    assert_includes response.body, "allowed_cadences:"
    assert_includes response.body, "recording_studio_notifications:deliver_rollups"
    assert_includes response.body, "deliver_rollup"
    assert_includes response.body, "an empty list permits no absolute hosts"
    assert_includes response.body, "always persisted without a root recording"
    assert_includes response.body, "first 20 source notifications"
    assert_includes response.body, "under the engine mount path"
    assert_includes response.body, "all notifications deliver and display individually"
    assert_includes response.body, "including the in-app channel"
    assert_includes response.body, "Crash-recovery timeout for rollups stuck in progress"
    assert_includes response.body, "without waiting for this timeout"
    assert_includes response.body, "<th class=\"py-2 pr-4 font-semibold\">Default</th>"
    assert_includes response.body, "[:individual]"
  end

  test "recordable types page renders configured recordables dynamically" do
    summary_data = create_recordable_type_summary_data

    get docs_recordable_types_path
    response_text = response.body.gsub(/\s+/, " ").strip

    assert_response :success
    assert_select "h1", text: "Recordable types"
    assert_includes(
      response.body,
      "The list below comes from RecordingStudio.recordable_declarations and v3 parent/root introspection."
    )
    assert_includes response.body, "Workspace"
    assert_includes response.body, "Folder"
    assert_includes response.body, "Page"
    assert_includes response_text, "Root recordable"
    assert_includes response_text, "Child recordable"
    assert_includes response_text, "Allowed parents: Workspace, Folder"
    assert_includes response_text, summary_data[:workspace]
    assert_includes response_text, summary_data[:folder]
  end

  test "recordable types page includes dummy app defaults" do
    get docs_recordable_types_path

    assert_response :success
    assert_includes response.body, "Workspace"
    assert_includes response.body, "Folder"
    assert_includes response.body, "Page"
  end

  test "recordings tree page renders successfully" do
    workspace = Workspace.create!(name: "Tree Workspace")
    root_recording = RecordingStudio.root_recording_for(workspace)
    folder = Folder.create!(name: "Reference")
    folder_recording = record_child(folder, root_recording, root_recording)
    page = Page.create!(title: "API")
    record_child(page, root_recording, folder_recording)

    get docs_recordings_tree_path

    assert_response :success
    assert_select "h1", text: "Recordings tree"
    assert_includes response.body, "Workspace: Tree Workspace"
    assert_includes response.body, "Folder: Reference"
    assert_includes response.body, "Page: API"
    refute_includes response.body, "Access boundary"
    refute_includes response.body, "Access: Admin"
    assert_select "div[role='tree']", count: 1
    assert_select "[role='treeitem']", minimum: 3
    refute_includes response.body, "Current structure"
    refute_includes response.body, "This tree is generated from RecordingStudio::Recording records"
  end

  test "gem_views page renders successfully" do
    get docs_gem_views_path
    assert_response :success
    assert_select "h1", text: "Gem Views"
    assert_select "a[href*='/docs/gem_view?view=']", minimum: 1
    refute_includes response.body, "app/views/recording_studio_notifications/home/index.html.erb"
  end

  test "methods page renders successfully" do
    get docs_methods_path
    assert_response :success
    assert_select "h1", text: "Methods"
    assert_includes response.body, "Public APIs for creating, querying, grouping, and managing notifications."
    assert_includes response.body, ".notify(**attributes)"
    assert_includes response.body, ".notify_each(recipients:, **attributes)"
    assert_includes response.body, ".register_notification_type(...) / .register_channel(...)"
    assert_includes response.body, ".for_recipient(recipient)"
    assert_includes response.body, "RecordingStudioNotifications::Notification.for_recipient(user).newest_first"
    assert_includes response.body, "#mark_read!"
    assert_includes response.body, "#notification_type_definition"
    assert_includes response.body, "Preference.cadence_for / .set_cadence!"
    assert_includes response.body, "Delivery status methods"
  end

  test "sidebar includes documentation links" do
    get docs_install_path

    assert_select %(a[href="#{docs_install_path}"]), text: /Install/
    assert_select %(a[href="#{docs_config_path}"]), text: /Config/
    assert_select %(a[href="#{docs_recordable_types_path}"]), text: /Recordable types/
    assert_select %(a[href="#{docs_recordings_tree_path}"]), text: /Recordings tree/
    assert_select %(a[href="#{docs_gem_views_path}"]), text: /Gem Views/
    assert_select %(a[href="#{docs_methods_path}"]), text: /Methods/
  end

  private

  def create_recordable_type_summary_data
    workspace_recordings_before = RecordingStudio::Recording.where(recordable_type: "Workspace").count
    workspaces_before = Workspace.count
    folder_recordings_before = RecordingStudio::Recording.where(recordable_type: "Folder").count
    folders_before = Folder.count

    workspace = Workspace.create!(name: "Counted Workspace")
    2.times do
      RecordingStudio.root_recording_for(Workspace.create!(name: "Counted Workspace #{SecureRandom.hex(4)}"))
    end

    root_recording = RecordingStudio.root_recording_for(workspace)
    folder = Folder.create!(name: "Counted Folder")
    record_child(folder, root_recording, root_recording)

    {
      workspace: recordable_type_summary(
        workspace_recordings_before + 3,
        workspaces_before + 3,
        "recordings",
        "recordables"
      ),
      folder: recordable_type_summary(
        folder_recordings_before + 1,
        folders_before + 1,
        "recording",
        "recordable"
      )
    }
  end

  def recordable_type_summary(recording_count, recordable_count, recording_label, recordable_label)
    "#{recording_count} #{recording_label} point to this type " \
      "• #{recordable_count} #{recordable_label} in the database"
  end

  def record_child(recordable, root_recording, parent_recording)
    RecordingStudio.record!(
      action: "created",
      recordable: recordable,
      root_recording: root_recording,
      parent_recording: parent_recording
    ).recording
  end
end
