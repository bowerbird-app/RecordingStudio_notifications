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

  test "marking a group read replaces the group for Turbo requests" do
    unread_notification = create_notification(title: "Unread in group", created_at: Time.current)
    read_notification = create_notification(title: "Read in group", created_at: Time.current, read_at: Time.current)
    group = RecordingStudioNotifications::Services::InboxGrouping.new(
      recipient: @user,
      notifications: [unread_notification, read_notification]
    ).call.first.groups.first

    patch "/notifications/notifications/mark_group_read", params: { group_id: group.id }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, "target=\"#{group.id}-container\""
    assert_includes response.body, "id=\"#{group.id}-container\""
    refute_includes response.body, "Mark all read"
    assert unread_notification.reload.read?
  end

  test "digest groups load notifications in batches of 20" do
    notifications = 41.times.map do |index|
      create_notification(
        title: "Digest page notification #{index + 1}",
        created_at: Time.current - index.minutes
      )
    end
    group = RecordingStudioNotifications::Services::InboxGrouping.new(
      recipient: @user,
      notifications: notifications
    ).call.first.groups.first

    get "/notifications"

    assert_response :success
    assert_includes response.body, "Digest page notification 1"
    assert_includes response.body, "Digest page notification 20"
    refute_includes response.body, "Digest page notification 21"
    assert_includes response.body, "id=\"#{group.id}-next-page-2\""
    assert_includes response.body, "/notifications/notifications/groups/#{group.id}/page"

    get "/notifications/notifications/groups/#{group.id}/page", params: { page: 2 }

    assert_response :success
    assert_equal "text/html; charset=utf-8", response.content_type
    assert_equal 1, response.body.scan("id=\"#{group.id}-next-page-2\"").size
    assert_includes response.body, "id=\"#{group.id}-next-page-3\""
    assert_includes response.body, "Digest page notification 21"
    assert_includes response.body, "Digest page notification 40"
    refute_includes response.body, "Digest page notification 41"
    assert_equal 1, response.body.scan("id=\"#{group.id}-next-page-3\"").size
    assert_includes response.body, "page=3"

    get "/notifications/notifications/groups/#{group.id}/page", params: { page: 3 }

    assert_response :success
    assert_includes response.body, "Digest page notification 41"
    assert_includes response.body, "id=\"#{group.id}-next-page-4\""
    refute_includes response.body, "src="
  end

  test "digest lazy-frame URLs stay HTML when rendered within an outer Turbo Stream page" do
    notifications = 21.times.map do |index|
      create_notification(
        title: "Turbo stream digest notification #{index + 1}",
        created_at: Time.current - index.minutes
      )
    end
    group = RecordingStudioNotifications::Services::InboxGrouping.new(
      recipient: @user,
      notifications: notifications
    ).call.first.groups.first

    get "/notifications/notifications", params: { format: :turbo_stream }

    assert_response :success
    assert_includes response.body, "groups/#{group.id}/page?page=2"
    refute_includes response.body, "groups/#{group.id}/page?format=turbo_stream"
  end

  test "unknown digest group pages are not found" do
    get "/notifications/notifications/groups/unknown-group/page"

    assert_response :not_found
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