# frozen_string_literal: true

module RecordingStudioNotifications
  module NotificationsHelper
    def notification_icon_for(notification)
      key = notification.respond_to?(:notification_type) ? notification.notification_type : nil
      return :bell if key.blank?

      definition = RecordingStudioNotifications.notification_types[key]
      definition&.icon || :bell
    end
  end
end
