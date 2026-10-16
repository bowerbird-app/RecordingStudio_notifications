# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationRootViewInboxTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = User.create!(
      email: "view-owner-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @viewer = User.create!(
      email: "view-member-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    Current.actor = @owner
    @workspace = Workspace.create!(name: "View inbox #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    bootstrap_owner!(@root, @owner)
    grant!(@root, @viewer, :view)
    RecordingStudioNotifications.notification_types.register(
      :root_view_inbox_test,
      label: "Root view inbox test",
      scope: :root,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    @title = "Message received #{SecureRandom.hex(4)}"
    @notification = RecordingStudioNotifications.notify(
      notification_type: :root_view_inbox_test,
      recipient: @viewer,
      actor: @owner,
      root_recording: @root,
      title: @title,
      idempotency_key: "root-view-inbox-#{SecureRandom.uuid}"
    )
    Current.actor = nil
  end

  teardown do
    Current.actor = nil
  end

  test "root-scoped notifications appear in the inbox and bell when the recipient has view on the root" do
    assert RecordingStudioAccessible.action_defined?(:view)
    assert RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)
    assert_not_nil @notification

    sign_in @viewer
    switch_to_root!(@root)

    get "/notifications"

    assert_response :success
    assert_includes response.body, @title

    get "/notifications/notifications/menu.json"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_operator payload.fetch("unread_count"), :>=, 1
    assert_includes payload.fetch("menu_html"), @title
  end

  private

  def bootstrap_owner!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: recording,
      actor: actor
    )
    raise result.error if result.failure?
  end

  def grant!(recording, actor, role)
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)

    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: @owner
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end

  def switch_to_root!(root)
    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: root.id,
        return_to: "/notifications"
      }
    }
  end
end
