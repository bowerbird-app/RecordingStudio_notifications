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

      def serialize_group(group:, href: nil, child_href_resolver: nil)
        latest_notification = group.latest_notification

        children = group.notifications.map do |notification|
          serialize(notification: notification, href: child_href_resolver&.call(notification))
        end

        serialize(notification: latest_notification, href: href).merge(
          unread: group.unread_count.positive?,
          rollup: true,
          children: children
        )
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
