# frozen_string_literal: true

module RecordingStudioNotifications
  module Admin
    class AllNotificationsSection < RecordingStudioAdmin::Section
      key "all_notifications"
      icon :bell
      title { Copy.t("admin.all_notifications.title", default: "All notifications") }
      subtitle { Copy.t("admin.all_notifications.subtitle", default: "Root-scoped and global notification overview") }

      link :notifications_table,
           text: ->(_context) { Copy.t("admin.all_notifications.open_table", default: "Open notifications table") },
           url: ->(context) { context.admin_screen_path("recording_studio_notifications_all_notifications") },
           style: :primary
    end
  end
end
