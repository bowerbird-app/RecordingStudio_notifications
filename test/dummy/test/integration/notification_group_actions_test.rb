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

  test "digest groups do not render a mark-all-read control" do
    create_notification(title: "Unread in group", created_at: Time.current)
    create_notification(title: "Another unread notification", created_at: 1.minute.ago)

    get "/notifications"

    assert_response :success
    assert_includes response.body, "Group action test"
    assert_includes response.body, ">Settings</a>"
    assert_includes response.body, "aria-label=\"2 unread notifications\""
    assert_includes response.body, "bg-red-600"
    assert_includes response.body, "relative inline-flex shrink-0"
    assert_includes response.body, "absolute -right-2 -top-2"
    assert_includes response.body, "inline-flex h-4 min-w-4 shrink-0"
    assert_includes response.body, "inline-block w-5 h-5"
    assert_includes response.body, "flex shrink-0 items-center gap-4"
    assert_includes response.body, "data-flat-pack--accordion-target=\"icon\""
    assert_includes response.body, "[&amp;_[data-flat-pack--accordion-target=icon]]:ml-4"
    assert_includes response.body, "[&amp;_[data-flat-pack--accordion-target=icon]]:self-center"
    refute_includes response.body, "Mark all read"
  end

  test "clear all clears unread notifications without marking them read" do
    unread_notification = create_notification(title: "Unread notification", created_at: Time.current)
    read_notification = create_notification(title: "Read notification", created_at: 1.minute.ago, read_at: Time.current)
    other_user = User.create!(
      email: "other-group-actions-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    other_users_notification = create_notification(
      title: "Other user's unread notification",
      created_at: Time.current,
      recipient: other_user
    )

    get "/notifications"

    assert_response :success
    assert_includes response.body, "Clear all"
    assert_includes response.body, ">Settings</a>"
    assert_operator response.body.index("Clear all"), :<, response.body.index(">Settings</a>")
    assert_includes response.body, "fp-red-dot"

    patch "/notifications/notifications/clear_all", as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, "target=\"notifications-title\""
    assert_includes response.body, "action=\"update\" target=\"notifications-list\""
    assert_includes response.body, "target=\"notifications_next_page\""
    refute_includes response.body, "Clear all"
    assert_includes response.body, ">Settings</a>"
    refute_includes response.body, "unread notifications\""
    refute_includes response.body, "fp-red-dot"
    assert unread_notification.reload.cleared_at.present?
    assert_nil unread_notification.read_at
    refute unread_notification.unread?
    assert read_notification.reload.read?
    assert_nil read_notification.cleared_at
    assert other_users_notification.reload.unread?

    get "/notifications"

    assert_response :success
    refute_includes response.body, "Clear all"
    refute_includes response.body, "fp-red-dot"
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

  private

  def create_notification(title:, created_at:, read_at: nil, recipient: @user)
    RecordingStudioNotifications::Notification.create!(
      recipient: recipient,
      notification_type: :group_action_test,
      title: title,
      created_at: created_at,
      updated_at: created_at,
      read_at: read_at
    )
  end
end