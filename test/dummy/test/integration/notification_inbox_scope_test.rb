# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationInboxScopeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = User.create!(
      email: "scope-owner-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @viewer = User.create!(
      email: "scope-member-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    Current.actor = @owner
    @root_a = root_for("Scope A #{SecureRandom.hex(4)}")
    @root_b = root_for("Scope B #{SecureRandom.hex(4)}")
    bootstrap_owner!(@root_a, @owner)
    bootstrap_owner!(@root_b, @owner)
    grant!(@root_a, @viewer, :view)
    grant!(@root_b, @viewer, :view)
    RecordingStudioNotifications.notification_types.register(
      :inbox_scope_test,
      label: "Inbox scope test",
      scope: :root,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    @title_a = "Scope A note #{SecureRandom.hex(4)}"
    @title_b = "Scope B note #{SecureRandom.hex(4)}"
    notify_on(@root_a, @title_a)
    notify_on(@root_b, @title_b)
    @original_scope = RecordingStudioNotifications.configuration.default_inbox_scope
    Current.actor = nil
    sign_in @viewer
    switch_to_root!(@root_a)
  end

  teardown do
    Current.actor = nil
    RecordingStudioNotifications.configuration.default_inbox_scope = @original_scope if @original_scope
  end

  test "the default inbox stays on the current root" do
    get "/notifications"

    assert_response :success
    assert_includes response.body, @title_a
    refute_includes response.body, @title_b
  end

  test "an allowlisted inbox_scope param lists every root and an invalid param falls back" do
    get "/notifications", params: { inbox_scope: "all" }

    assert_response :success
    assert_includes response.body, @title_a
    assert_includes response.body, @title_b

    get "/notifications/notifications/menu.json", params: { inbox_scope: "all" }

    assert_response :success
    menu = JSON.parse(response.body).fetch("menu_html")
    assert_includes menu, @title_a
    assert_includes menu, @title_b

    get "/notifications", params: { inbox_scope: "sideways" }

    assert_response :success
    assert_includes response.body, @title_a
    refute_includes response.body, @title_b
  end

  test "config default all lists every root until a current_root param narrows it" do
    RecordingStudioNotifications.configuration.default_inbox_scope = "all"

    get "/notifications"

    assert_response :success
    assert_includes response.body, @title_a
    assert_includes response.body, @title_b

    get "/notifications", params: { inbox_scope: "current_root" }

    assert_response :success
    assert_includes response.body, @title_a
    refute_includes response.body, @title_b
  end

  private

  def root_for(name)
    RecordingStudio.root_recording_for(Workspace.create!(name: name))
  end

  def notify_on(root, title)
    RecordingStudioNotifications.notify(
      notification_type: :inbox_scope_test,
      recipient: @viewer,
      actor: @owner,
      root_recording: root,
      title: title,
      idempotency_key: "inbox-scope-#{SecureRandom.uuid}"
    )
  end

  def bootstrap_owner!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
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
    ensure_switch_page_view!(@viewer)
    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: root.id,
        return_to: "/notifications"
      }
    }
  end
end
