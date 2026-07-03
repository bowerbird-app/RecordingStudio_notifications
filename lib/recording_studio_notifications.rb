# frozen_string_literal: true

require "recording_studio_notifications/version"
require "recording_studio_notifications/engine"
require "recording_studio_notifications/configuration"
require "recording_studio_notifications/notification_type_registry"
require "recording_studio_notifications/channel_registry"
require "recording_studio_notifications/url_safety"
require "recording_studio_notifications/services/notify"
require "recording_studio_notifications/services/root_resolver"
require "recording_studio_notifications/services/notification_authorization"

if defined?(RecordingStudioAdmin)
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
  end
end
