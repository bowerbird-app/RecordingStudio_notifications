# frozen_string_literal: true

require "test_helper"

class AdminI18nTest < Minitest::Test
  Copy = RecordingStudioNotifications::Copy

  def test_admin_scope_and_status_cell_labels_use_literal_english
    I18n.with_locale(:en) do
      assert_equal "All notifications", Copy.t("admin.all_notifications.title")
      assert_equal "Root-scoped and global notification overview", Copy.t("admin.all_notifications.subtitle")
      assert_equal "Notifications", Copy.t("admin.all_notifications.summary")
      assert_equal "Open notifications table", Copy.t("admin.all_notifications.open_table")
      assert_equal "Type", Copy.t("admin.all_notifications.columns.type")
      assert_equal "Scope", Copy.t("admin.all_notifications.columns.scope")
      assert_equal "Root", Copy.t("admin.all_notifications.scope.root")
      assert_equal "Global", Copy.t("admin.all_notifications.scope.global")
      assert_equal "Read", Copy.t("admin.all_notifications.status.read")
      assert_equal "Unread", Copy.t("admin.all_notifications.status.unread")
      assert_equal "-", Copy.t("admin.all_notifications.actor.none")
    end
  end

  def test_admin_screen_source_calls_copy_for_chrome
    source = File.read(File.expand_path("../lib/recording_studio_notifications/admin/all_notifications_screen.rb", __dir__))
    section = File.read(File.expand_path("../lib/recording_studio_notifications/admin/all_notifications_section.rb", __dir__))

    assert_includes source, 'Copy.t("admin.all_notifications.title")'
    assert_includes source, 'Copy.t("admin.all_notifications.subtitle")'
    assert_includes source, 'Copy.t("admin.all_notifications.summary")'
    assert_includes source, 'Copy.t("admin.all_notifications.scope.root")'
    assert_includes source, 'Copy.t("admin.all_notifications.status.read")'
    assert_includes section, 'Copy.t("admin.all_notifications.open_table")'
    assert_includes source, 'title: "Type"'
    refute_includes source, 'title "All notifications"'
    refute_includes section, 'text: "Open notifications table"'
  end
end

