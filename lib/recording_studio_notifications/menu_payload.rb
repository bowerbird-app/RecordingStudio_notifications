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
