# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    module NotifyValidation
      private

      def validate_inputs!
        raise ArgumentError, "recipient is required" unless @recipient
        raise ArgumentError, "title is required" if @title.to_s.blank?
        raise ArgumentError, "notification_type is not registered" unless type_definition
        raise ArgumentError, "root_recording is required" if type_definition.scope == :root && resolved_root_recording.blank?
        raise ArgumentError, "root_recording does not match recording or notifiable" unless consistent_root_scope?

        validate_required_channels_available!(channel_keys)
        validate_registered_channels!
        validate_type_available_channels!
        validate_rollup_channel_support!
        UrlSafety.sanitize!(@url)
      end

      def validate_registered_channels!
        unregistered_channel = channel_keys.find do |channel|
          !RecordingStudioNotifications.channels.registered?(channel)
        end
        raise ArgumentError, "channel is not registered: #{unregistered_channel}" if unregistered_channel
      end

      def validate_type_available_channels!
        return unless type_definition.available_channels

        unavailable_channel = channel_keys.find { |channel| !type_definition.available_channels.include?(channel) }
        return unless unavailable_channel

        raise ArgumentError,
              "channel is not available for #{@notification_type}: #{unavailable_channel}"
      end

      def validate_rollup_channel_support!
        unsupported_rollup_channel = channel_keys.find do |channel|
          deferred_rollup_channel?(channel) && !RecordingStudioNotifications.channels.fetch(channel).respond_to?(:deliver_rollup)
        end
        raise ArgumentError, "channel does not support grouped delivery: #{unsupported_rollup_channel}" if unsupported_rollup_channel
      end
    end
  end
end
