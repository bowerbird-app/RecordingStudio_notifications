# frozen_string_literal: true

module RecordingStudioNotifications
  module NotificationsHelper
    def notification_icon_for(notification)
      key = notification.respond_to?(:notification_type) ? notification.notification_type : nil
      return :bell if key.blank?

      definition = RecordingStudioNotifications.notification_types[key]
      definition&.icon || :bell
    end

    def notification_leading_icon(notification)
      icon_classes = ["text-[var(--surface-muted-content-color)]"]
      icon_classes << "fp-red-dot" if notification.respond_to?(:unread?) && notification.unread?

      render FlatPack::Shared::IconComponent.new(
        name: notification_icon_for(notification),
        size: :md,
        class: icon_classes.join(" ")
      )
    end
  end
end
