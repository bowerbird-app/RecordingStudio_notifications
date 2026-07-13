# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationGroupActionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "group-actions-#{SecureRandom.uuid}@example.test") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    RecordingStudioNotifications.notification_types.register(
      :group_action_test,
      label: "Group action test",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app],
      allowed_cadences: [:daily],
      default_cadence: :daily
    )
    sign_in @user
  end

  test "marking a group read updates only its visible unread source notifications" do
    in_group_unread = create_notification(title: "Unread in group", created_at: Time.current)
    in_group_read = create_notification(title: "Read in group", created_at: Time.current, read_at: Time.current)
    outside_group = create_notification(title: "Unread outside group", created_at: 2.days.ago)
    group = RecordingStudioNotifications::Services::InboxGrouping.new(
      recipient: @user,
      notifications: [in_group_unread, in_group_read]
    ).call.first.groups.first

    get "/notifications"

    assert_response :success
    assert_includes response.body, "Mark all read"
    assert_includes response.body, "Group action test"
    assert_includes response.body, "fp-red-dot"
    assert_includes response.body, "unread"

    patch "/notifications/notifications/mark_group_read", params: { group_id: group.id }

    assert_redirected_to "/notifications/notifications"
    assert in_group_unread.reload.read?
    assert in_group_read.reload.read?
    assert outside_group.reload.unread?
  end

  test "unknown group ids do not update notifications" do
    notification = create_notification(title: "Unread notification", created_at: Time.current)

    patch "/notifications/notifications/mark_group_read", params: { group_id: "unknown-group" }

    assert_response :not_found
    assert notification.reload.unread?
  end

  private

  def create_notification(title:, created_at:, read_at: nil)
    RecordingStudioNotifications::Notification.create!(
      recipient: @user,
      notification_type: :group_action_test,
      title: title,
      created_at: created_at,
      updated_at: created_at,
      read_at: read_at
    )
  end
end