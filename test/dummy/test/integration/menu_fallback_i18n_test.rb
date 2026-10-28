# frozen_string_literal: true

require "test_helper"

class MenuFallbackI18nTest < ActionDispatch::IntegrationTest
  test "non FlatPack notification fallback renders literal English bell label" do
    original = FlatPack::Notification::Component if defined?(FlatPack::Notification::Component)
    FlatPack::Notification.send(:remove_const, :Component) if defined?(FlatPack::Notification::Component)

    html = ApplicationController.render(
      partial: "recording_studio_notifications/notifications/menu_component",
      locals: {
        unread_count: 3,
        notifications: [],
        see_all_href: "/notifications"
      }
    )

    assert_includes html, "Notifications (3)"
    refute_includes html, "translation missing"
  ensure
    FlatPack::Notification.const_set(:Component, original) if original && !defined?(FlatPack::Notification::Component)
  end

  test "non FlatPack fallback with zero unread uses plain Notifications label" do
    original = FlatPack::Notification::Component if defined?(FlatPack::Notification::Component)
    FlatPack::Notification.send(:remove_const, :Component) if defined?(FlatPack::Notification::Component)

    html = ApplicationController.render(
      partial: "recording_studio_notifications/notifications/menu_component",
      locals: {
        unread_count: 0,
        notifications: [],
        see_all_href: "/notifications"
      }
    )

    assert_includes html, "Notifications"
    refute_includes html, "Notifications (0)"
  ensure
    FlatPack::Notification.const_set(:Component, original) if original && !defined?(FlatPack::Notification::Component)
  end
end
