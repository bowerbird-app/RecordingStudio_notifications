# frozen_string_literal: true

require "test_helper"
require "recording_studio_notifications/services/inbox_grouping"

class MenuPayloadTest < Minitest::Test
  NotificationStruct = Struct.new(
    :id,
    :title,
    :body,
    :created_at,
    :notification_type,
    :unread,
    keyword_init: true
  ) do
    def unread?
      unread
    end
  end

  def test_serialize_group_builds_rollup_payload_with_children
    newest = notification(
      id: 2,
      title: "Build completed",
      body: "Your export is ready to download.",
      created_at: Time.utc(2026, 7, 3, 9, 18, 0),
      unread: false
    )
    older = notification(
      id: 1,
      title: "Build started",
      body: "Your export job started.",
      created_at: Time.utc(2026, 7, 3, 9, 10, 0),
      unread: true
    )

    group = RecordingStudioNotifications::Services::InboxGrouping::Group.new(
      notification_type: "system_alert",
      notification_type_label: "System alert",
      cadence: :daily,
      period_starts_at: Time.utc(2026, 7, 3, 0, 0, 0),
      period_ends_at: Time.utc(2026, 7, 4, 0, 0, 0),
      time_zone: ActiveSupport::TimeZone["UTC"],
      notifications: [newest, older],
      id: "notification-group-system-alert-daily-1"
    )

    payload = RecordingStudioNotifications::MenuPayload.serialize_group(
      group: group,
      child_href_resolver: ->(notification) { "/notifications/#{notification.id}" }
    )

    assert_equal "Build completed", payload[:title]
    assert_equal "Your export is ready to download.", payload[:body]
    assert_nil payload[:href]
    assert_equal true, payload[:rollup]
    assert_equal true, payload[:unread]
    assert_equal Time.utc(2026, 7, 3, 9, 18, 0), payload[:time]
    assert_equal :bell, payload[:icon]

    assert_equal 2, payload[:children].size
    assert_equal "Build completed", payload[:children][0][:title]
    assert_equal "/notifications/2", payload[:children][0][:href]
    assert_equal "Build started", payload[:children][1][:title]
    assert_equal "/notifications/1", payload[:children][1][:href]
  end

  private

  def notification(id:, title:, body:, created_at:, unread:)
    NotificationStruct.new(
      id: id,
      title: title,
      body: body,
      created_at: created_at,
      notification_type: nil,
      unread: unread
    )
  end
end
