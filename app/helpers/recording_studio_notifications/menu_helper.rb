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
              see_all_href: recording_studio_notifications.notifications_path,
              bell_label: Copy.t("menu.title", default: "Notifications"),
              empty_text: Copy.t("menu.empty", default: "No recent notifications")
            }
          )
        end
      end
    rescue StandardError
      nil
    end

    def notification_menu_leading_icon(notification)
      name = notification_menu_value(notification, :icon).presence || :bell
      if notification_menu_rollup?(notification)
        return notification_count_badge(
          notification_named_leading_icon(name),
          notification_menu_rollup_unread_count(notification)
        )
      end

      notification_named_leading_icon(name, unread: notification_menu_unread?(notification))
    end

    def notification_menu_value(notification, key)
      return unless notification.respond_to?(:[])

      value = notification[key]
      value.nil? ? notification[key.to_s] : value
    end

    def notification_menu_unread?(notification)
      notification_menu_value(notification, :unread) == true
    end

    private

    def notification_menu_rollup?(notification)
      notification_menu_value(notification, :rollup) == true && notification_menu_children(notification).any?
    end

    def notification_menu_rollup_unread_count(notification)
      notification_menu_children(notification).count { |child| notification_menu_unread?(child) }
    end

    def notification_menu_children(notification)
      Array(notification_menu_value(notification, :children)).select { |child| child.respond_to?(:[]) }
    end

    def normalized_polling_interval
      interval = RecordingStudioNotifications.configuration.polling_interval_seconds.to_i
      return 60 if interval <= 0

      interval
    end
  end
end
