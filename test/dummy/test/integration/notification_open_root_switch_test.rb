# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationOpenRootSwitchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = User.create!(
      email: "open-switch-owner-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @viewer = User.create!(
      email: "open-switch-member-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    Current.actor = @owner
    @workspace_a = Workspace.create!(name: "Open switch A #{SecureRandom.hex(4)}")
    @workspace_b = Workspace.create!(name: "Open switch B #{SecureRandom.hex(4)}")
    @root_a = RecordingStudio.root_recording_for(@workspace_a)
    @root_b = RecordingStudio.root_recording_for(@workspace_b)
    bootstrap_owner!(@root_a, @owner)
    bootstrap_owner!(@root_b, @owner)
    grant!(@root_a, @viewer, :view)
    grant!(@root_b, @viewer, :view)
    RecordingStudioNotifications.notification_types.register(
      :open_root_switch_test,
      label: "Open root switch test",
      scope: :root,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    RecordingStudioNotifications.notification_types.register(
      :open_root_switch_global,
      label: "Open root switch global",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app],
      allowed_cadences: [:individual],
      default_cadence: :individual
    )
    Current.actor = nil
    sign_in @viewer
    switch_to_root!(@root_a)
  end

  teardown do
    Current.actor = nil
    restore_switch_root!
  end

  test "opening a notification from another root switches the selection then redirects" do
    title = "From the other workspace #{SecureRandom.hex(4)}"
    notification = notify_on(@root_b, title: title, url: "/")

    get "/notifications/notifications/#{notification.id}/open", params: { inbox_scope: "all" }

    assert_redirected_to "/"
    assert notification.reload.read?
    assert_equal @root_b.id, persisted_selection.root_recording_id
    assert_equal "all_workspaces", persisted_selection.scope_key

    get "/notifications"

    assert_response :success
    assert_includes response.body, title

    get "/"

    assert_response :success
    assert_includes response.body, @workspace_b.name
  end

  test "opening a notification in the current root does not switch" do
    notification = notify_on(@root_a, title: "Already here", url: "/")
    switch_calls = 0
    replace_switch_root! ->(**) { switch_calls += 1 }

    get "/notifications/notifications/#{notification.id}/open"

    assert_redirected_to "/"
    assert_equal 0, switch_calls
    assert_equal @root_a.id, persisted_selection.root_recording_id
  end

  test "opening still redirects when the switch is refused" do
    notification = notify_on(@root_b, title: "Switch refused", url: "/")
    replace_switch_root! ->(**) { raise StandardError, "selected root is not available" }

    get "/notifications/notifications/#{notification.id}/open"

    assert_redirected_to "/"
    assert notification.reload.read?
    assert_equal @root_a.id, persisted_selection.root_recording_id
  end

  test "opening still redirects when Root Switchable cannot switch" do
    notification = notify_on(@root_b, title: "No switcher", url: "/")
    hide_switch_root!

    get "/notifications/notifications/#{notification.id}/open"

    assert_redirected_to "/"
    assert notification.reload.read?
    assert_equal @root_a.id, persisted_selection.root_recording_id
  end

  test "opening a rootless notification does not switch" do
    notification = RecordingStudioNotifications.notify(
      notification_type: :open_root_switch_global,
      recipient: @viewer,
      title: "No workspace",
      url: "/",
      deliver_later: false,
      idempotency_key: "open-root-switch-global-#{SecureRandom.uuid}"
    )
    switch_calls = 0
    replace_switch_root! ->(**) { switch_calls += 1 }

    get "/notifications/notifications/#{notification.id}/open"

    assert_redirected_to "/"
    assert_equal 0, switch_calls
    assert_equal @root_a.id, persisted_selection.root_recording_id
  end

  private

  def notify_on(root, title:, url:)
    RecordingStudioNotifications.notify(
      notification_type: :open_root_switch_test,
      recipient: @viewer,
      actor: @owner,
      root_recording: root,
      title: title,
      url: url,
      deliver_later: false,
      idempotency_key: "open-root-switch-#{SecureRandom.uuid}"
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
    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: root.id,
        return_to: "/notifications"
      }
    }
  end

  def persisted_selection
    RecordingStudio::RootSwitchable::Selection.find_by!(
      actor: @viewer,
      scope_key: "all_workspaces"
    )
  end

  def replace_switch_root!(implementation)
    restore_switch_root!
    singleton = RecordingStudio::RootSwitchable.singleton_class
    singleton.alias_method :__test_orig_switch_root, :switch_root
    @switch_root_replaced = true
    singleton.define_method(:switch_root) do |**kwargs|
      implementation.call(**kwargs)
    end
  end

  def hide_switch_root!
    restore_switch_root!
    singleton = RecordingStudio::RootSwitchable.singleton_class
    singleton.alias_method :__test_orig_switch_root, :switch_root
    singleton.undef_method :switch_root
    @switch_root_replaced = true
  end

  def restore_switch_root!
    return unless @switch_root_replaced

    singleton = RecordingStudio::RootSwitchable.singleton_class
    if singleton.method_defined?(:switch_root) || singleton.private_method_defined?(:switch_root)
      singleton.remove_method :switch_root
    end
    singleton.alias_method :switch_root, :__test_orig_switch_root
    singleton.remove_method :__test_orig_switch_root
    @switch_root_replaced = false
  end
end
