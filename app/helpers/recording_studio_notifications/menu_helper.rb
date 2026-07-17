# frozen_string_literal: true

module RecordingStudioNotifications
  module MenuHelper
    def recording_studio_notifications_async_menu(recipient:, limit: 5)
      return if recipient.blank?

      interval_seconds = normalized_polling_interval

      content_tag(
        :div,
        data: {
          controller: "recording-studio-notifications--notification-polling",
          "recording-studio-notifications--notification-polling-url-value":
            recording_studio_notifications.menu_notifications_path(format: :json),
          "recording-studio-notifications--notification-polling-interval-value": interval_seconds,
          "recording-studio-notifications--notification-polling-limit-value": limit
        }
      ) do
        content_tag(
          :div,
          data: { "recording-studio-notifications--notification-polling-target": "content" }
        ) do
          render(
            partial: "recording_studio_notifications/notifications/menu_component",
            locals: {
              unread_count: 0,
              notifications: [],
              see_all_href: recording_studio_notifications.notifications_path
            }
          )
        end
      end
    rescue StandardError
      nil
    end

    private

    def normalized_polling_interval
      interval = RecordingStudioNotifications.configuration.polling_interval_seconds.to_i
      return 60 if interval <= 0

      interval
    end
  end
end
