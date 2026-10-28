# frozen_string_literal: true

require "test_helper"

class MenuFallbackI18nTest < ActionDispatch::IntegrationTest
  test "non FlatPack notification fallback renders literal English bell label" do
    html = render_menu_without_flatpack_component(
      unread_count: 3,
      notifications: [],
      see_all_href: "/notifications"
    )

    assert_includes html, "Notifications (3)"
    refute_includes html, "translation missing"
  end

  test "non FlatPack fallback with zero unread uses plain Notifications label" do
    html = render_menu_without_flatpack_component(
      unread_count: 0,
      notifications: [],
      see_all_href: "/notifications"
    )

    assert_includes html, "Notifications"
    refute_includes html, "Notifications (0)"
  end

  private

  def render_menu_without_flatpack_component(**locals)
    view = ApplicationController.view_context
    view.stub(:recording_studio_notifications_flatpack_notification_component, nil) do
      view.render(
        partial: "recording_studio_notifications/notifications/menu_component",
        locals: locals
      )
    end
  end
end
