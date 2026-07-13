# frozen_string_literal: true

module RecordingStudioNotifications
  class MenuPayload
    class << self
      def serialize(notification:, href:)
        {
          title: notification.title,
          body: notification.body,
          href: href,
          unread: notification.unread?,
          time: notification.created_at,
          icon: icon_for(notification)
        }
      end

      def serialize_group(group:, href:)
        latest_notification = group.latest_notification

        {
          title: "#{group.notification_type_label}: #{group.period_label}",
          body: "#{group.unread_count} unread · #{group.notifications.size} notifications",
          href: href,
          unread: group.unread_count.positive?,
          time: latest_notification.created_at,
          icon: icon_for(latest_notification)
        }
      end

      private

      def icon_for(notification)
        key = notification.respond_to?(:notification_type) ? notification.notification_type : nil
        return :bell if key.blank?

        definition = RecordingStudioNotifications.notification_types[key]
        definition&.icon || :bell
      end
    end
  end
end
