# frozen_string_literal: true

module RecordingStudioNotifications
  module NotificationUrl
    def notification_url(notification)
      options = absolute_url_options
      raise ArgumentError, "Set config.action_mailer.default_url_options[:host] so notification_url is absolute" if options[:host].blank?

      mounted_notification_routes.open_notification_url(notification, **options)
    end
  end
end
