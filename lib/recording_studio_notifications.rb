# frozen_string_literal: true

require "recording_studio_notifications/version"
require "recording_studio_notifications/copy"
require "recording_studio_notifications/engine"
require "recording_studio_notifications/configuration"
require "recording_studio_notifications/notification_type_registry"
require "recording_studio_notifications/channel_registry"
require "recording_studio_notifications/url_safety"
require "recording_studio_notifications/menu_payload"
require "recording_studio_notifications/services/notify"
require "recording_studio_notifications/services/cadence_period"
require "recording_studio_notifications/services/inbox_grouping"
require "recording_studio_notifications/services/root_resolver"
require "recording_studio_notifications/services/notification_authorization"
require "recording_studio_notifications/delivery_payload_registry"
require "recording_studio_notifications/metrics"

if defined?(RecordingStudioAdmin)
  require "recording_studio_notifications/admin/failed_deliveries_chart"
  require "recording_studio_notifications/admin/failed_deliveries_screen_chart"
  require "recording_studio_notifications/admin/failed_deliveries_widget"
  require "recording_studio_notifications/admin/failed_deliveries_screen"
  require "recording_studio_notifications/admin/all_notifications_screen"
  require "recording_studio_notifications/admin/all_notifications_section"
end

module RecordingStudioNotifications
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def notification_types
      configuration.notification_types
    end

    def channels
      configuration.channels
    end

    def register_notification_type(...)
      notification_types.register(...)
    end

    def register_channel(...)
      channels.register(...)
    end

    def notify(**attributes)
      Services::Notify.call(**attributes)
    end

    def notify_each(recipients:, **attributes)
      Array(recipients).map do |recipient|
        notify(recipient: recipient, **attributes)
      end
    end

    def unsubscribe_purpose(notification_type, channel)
      "recording_studio_notifications.unsubscribe.#{notification_type.to_s.strip}.#{channel.to_s.strip}"
    end

    def unsubscribe_token(recipient:, notification_type:, channel:)
      recipient.to_sgid(
        for: unsubscribe_purpose(notification_type, channel),
        expires_in: configuration.unsubscribe_expires_in
      ).to_s
    end

    def unsubscribe_url(recipient:, notification_type:, channel:)
      mounted_notification_routes.unsubscribe_url(
        notification_type.to_s,
        channel.to_s,
        token: unsubscribe_token(recipient:, notification_type:, channel:),
        **absolute_url_options
      )
    end

    def list_unsubscribe_headers(recipient:, notification_type:, channel:)
      url = unsubscribe_url(recipient:, notification_type:, channel:)
      {
        "List-Unsubscribe" => "<#{url}>",
        "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click"
      }
    end

    def delivery_payload_resolvers
      @delivery_payload_resolvers ||= DeliveryPayloadRegistry.new
    end

    def register_delivery_payload_resolver(type, &)
      delivery_payload_resolvers.register(type, &)
    end

    def delivery_payload_for(notification:, delivery:)
      resolved = delivery_payload_resolvers.resolve(notification: notification, delivery: delivery)
      return persisted_delivery_payload(notification) if resolved.nil?

      normalize_delivery_payload(resolved)
    rescue StandardError
      raise DeliveryPayloadError, "delivery payload resolution failed"
    end

    private

    def persisted_delivery_payload(notification)
      DeliveryPayload.new(
        title: notification.title,
        body: notification.body,
        url: notification.url
      )
    end

    def mounted_notification_routes
      Engine.routes.url_helpers
    end

    def absolute_url_options
      routes = Rails.application.routes.default_url_options || {}
      mailer = Rails.application.config.action_mailer.default_url_options || {}
      routes.merge(mailer).symbolize_keys
    end

    def normalize_delivery_payload(value)
      case value
      when DeliveryPayload
        value
      when Hash
        DeliveryPayload.new(
          title: value[:title] || value["title"],
          body: value[:body] || value["body"],
          url: value[:url] || value["url"]
        )
      else
        raise DeliveryPayloadError, "delivery payload resolution failed"
      end
    end
  end
end
