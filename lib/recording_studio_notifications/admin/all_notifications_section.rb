# frozen_string_literal: true

module RecordingStudioNotifications
  module Admin
    class AllNotificationsSection < RecordingStudioAdmin::Section
      key "all_notifications"
      icon :bell
      title "All notifications"
      subtitle "Root-scoped and global notification overview"

      link :notifications_table,
           text: "Open notifications table",
           url: ->(context) { context.admin_screen_path("recording_studio_notifications_all_notifications") },
           style: :primary
    end
  end
end
