# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationMemberActionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      email: "member-actions-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @other = User.create!(
      email: "member-actions-other-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :member_action_global,
      label: "Member action global",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app],
      allowed_cadences: [:individual],
      default_cadence: :individual
    )
    RecordingStudioNotifications.notification_types.register(
      :member_action_daily,
      label: "Member action daily",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app],
      allowed_cadences: [:daily],
      default_cadence: :daily
    )
    RecordingStudioNotifications.notification_types.register(
      :member_action_root,
      label: "Member action root",
      scope: :root,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    sign_in @user
  end

  test "show open and state changes follow the notification" do
    notification = create_global(type: :member_action_global, title: "Open me", url: "/covered-open-target")

    get "/notifications/notifications/#{notification.id}"

    assert_response :success
    assert_includes response.body, "Open me"
    group = Struct.new(:id).new("coverage-group")
    assert_equal "coverage-group-container",
                 RecordingStudioNotifications::NotificationsController.new.send(:notification_group_dom_id, group)

    get "/notifications/notifications/#{notification.id}/open"

    assert_redirected_to "/covered-open-target"
    assert notification.reload.read?

    notification.mark_unread!
    patch "/notifications/notifications/#{notification.id}/mark_read"
    assert_redirected_to "/notifications/notifications/#{notification.id}"
    assert notification.reload.read?

    patch "/notifications/notifications/#{notification.id}/mark_unread"
    assert_redirected_to "/notifications/notifications/#{notification.id}"
    assert notification.reload.unread?

    patch "/notifications/notifications/#{notification.id}/archive"
    assert_redirected_to "/notifications/notifications/#{notification.id}"
    assert notification.reload.archived?

    patch "/notifications/notifications/#{notification.id}/unarchive"
    assert_redirected_to "/notifications/notifications/#{notification.id}"
    refute notification.reload.archived?
  end

  test "clear all over HTML redirects back with see other" do
    notification = create_global(type: :member_action_global, title: "Clear over HTML")

    patch "/notifications/notifications/clear_all"

    assert_response :see_other
    assert_redirected_to "/notifications/notifications"
    assert notification.reload.cleared_at.present?
    assert_nil notification.read_at
  end

  test "show escapes html in the title" do
    notification = create_global(type: :member_action_global, title: "<script>alert(1)</script>")

    get "/notifications/notifications/#{notification.id}"

    assert_response :success
    refute_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;"
    refute_includes response.body, "&amp;lt;"
  end

  test "show keeps apostrophes in the title" do
    notification = create_global(type: :member_action_global, title: "Don't")

    get "/notifications/notifications/#{notification.id}"

    assert_response :success
    assert_select "h1" do |elements|
      heading = elements.first.text
      assert_includes heading, "Don't"
      refute_includes heading, "&#39;"
      refute_includes heading, "&amp;#39;"
    end
  end

  test "open falls back when the stored url is unsafe" do
    notification = create_global(type: :member_action_global, title: "Unsafe open", url: "/covered-open-target")
    notification.mark_read!
    notification.update_column(:url, "javascript:alert(1)")

    get "/notifications/notifications/#{notification.id}/open"

    assert_redirected_to "/notifications/notifications/#{notification.id}"
  end

  test "another recipient's notification is not found" do
    notification = create_global(type: :member_action_global, title: "Someone else", recipient: @other)

    get "/notifications/notifications/#{notification.id}"

    assert_response :not_found
  end

  test "a root notification without view is forbidden" do
    notification = create_root_notification

    get "/notifications/notifications/#{notification.id}"
    assert_response :forbidden

    get "/notifications/notifications/#{notification.id}/open"
    assert_response :forbidden

    patch "/notifications/notifications/#{notification.id}/mark_read"
    assert_response :forbidden

    patch "/notifications/notifications/#{notification.id}/mark_unread"
    assert_response :forbidden

    patch "/notifications/notifications/#{notification.id}/archive"
    assert_response :forbidden

    patch "/notifications/notifications/#{notification.id}/unarchive"
    assert_response :forbidden

    assert notification.reload.unread?
    refute notification.archived?
  end

  test "the menu caps the requested limit and includes rollup children" do
    6.times do |index|
      create_global(type: :member_action_global, title: "Menu item #{index}")
    end
    rollup = RecordingStudioNotifications::Notification.create!(
      recipient: @user,
      notification_type: "member_action_daily",
      title: "Rolled up item"
    )

    get "/notifications/notifications/menu.json", params: { limit: 0 }

    assert_response :success
    capped = JSON.parse(response.body).fetch("notifications")
    assert_equal 5, capped.size

    get "/notifications/notifications/menu.json", params: { limit: 100 }

    assert_response :success
    payload = JSON.parse(response.body).fetch("notifications")
    assert_operator payload.size, :<=, 25
    assert_operator payload.size, :>, 5
    rolled = payload.find { |item| item["title"] == "Member action daily" || item["body"].to_s.include?("Rolled") || item["rollup"] }
    individual = payload.find { |item| item["title"].to_s.start_with?("Menu item") }

    assert individual
    refute individual.key?("rollup")
    assert rolled.fetch("rollup")
    assert_includes rolled.fetch("children").map { |child| child["title"] }, rollup.title
  end

  private

  def create_global(type:, title:, recipient: @user, url: nil)
    RecordingStudioNotifications.notify(
      notification_type: type,
      recipient: recipient,
      title: title,
      url: url,
      deliver_later: false,
      idempotency_key: "member-action-#{SecureRandom.uuid}"
    )
  end

  def create_root_notification
    Current.actor = @user
    root = RecordingStudio.root_recording_for(Workspace.create!(name: "Member root #{SecureRandom.hex(4)}"))
    RecordingStudioNotifications.notify(
      notification_type: :member_action_root,
      recipient: @user,
      root_recording: root,
      title: "Hidden root notification",
      deliver_later: false,
      idempotency_key: "member-action-root-#{SecureRandom.uuid}"
    )
  ensure
    Current.actor = nil
  end
end
