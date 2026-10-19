# frozen_string_literal: true

return unless defined?(RecordingStudioAdmin)

module RecordingStudioNotifications
  module Admin
    class AllNotificationsSection < RecordingStudioAdmin::Section
      key "all_notifications"
      icon :bell
      blast_radius :site
      title { Copy.t("admin.all_notifications.title", default: "All notifications") }
      subtitle { Copy.t("admin.all_notifications.subtitle", default: "Root-scoped and global notification overview") }

      link :notifications_table,
           text: ->(_context) { Copy.t("admin.all_notifications.open_table", default: "Open notifications table") },
           url: ->(context) { context.admin_screen_path("recording_studio_notifications_all_notifications") },
           style: :primary

      link :failed_deliveries,
           text: ->(_context) { Copy.t("admin.failed_deliveries.open", default: "See the chart") },
           url: ->(context) { context.admin_screen_path(FailedDeliveriesChart::SCREEN_KEY) },
           style: :secondary

      widget FailedDeliveriesChart::WIDGET_KEY, view_variant: :compact
    end
  end
end
