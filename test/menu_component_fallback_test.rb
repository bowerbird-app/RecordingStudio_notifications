# frozen_string_literal: true

require "test_helper"

class MenuComponentFallbackTest < Minitest::Test
  def test_menu_component_fallback_branch_uses_copy_for_literal_english
    partial = File.read(
      File.expand_path(
        "../app/views/recording_studio_notifications/notifications/_menu_component.html.erb",
        __dir__
      )
    )

    assert_includes partial, "defined?(FlatPack::Notification::Component)"
    assert_includes partial, 'Copy.t("menu.title_with_count", count: unread_count)'
    assert_includes partial, '"menu.title"'
    assert_includes partial, '"menu.empty"'
  end

  def test_menu_title_with_count_english_is_unchanged
    I18n.with_locale(:en) do
      assert_equal "Notifications (3)", RecordingStudioNotifications::Copy.t("menu.title_with_count", count: 3)
      assert_equal "Notifications", RecordingStudioNotifications::Copy.t("menu.title")
      assert_equal "No recent notifications", RecordingStudioNotifications::Copy.t("menu.empty")
    end
  end
end
