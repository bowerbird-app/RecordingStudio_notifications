# frozen_string_literal: true

module RecordingStudioNotifications
  module NotificationUrl
    def notification_url(notification)
      options = notification_url_options
      raise ArgumentError, "Set config.action_mailer.default_url_options[:host] so notification_url is absolute" if options[:host].blank?

      mounted_notification_routes.open_notification_url(notification, **options)
    end

    private

    def notification_url_options
      routes = Rails.application.routes.default_url_options || {}
      mailer = Rails.application.config.action_mailer.default_url_options || {}
      routes.merge(mailer.compact_blank).symbolize_keys
    end
  end
end
