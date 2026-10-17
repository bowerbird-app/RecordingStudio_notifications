# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    module InboxFlag
      private

      def requested_optional_channels
        channels = Array(@requested_channels || type_definition.default_channels ||
          RecordingStudioNotifications.configuration.default_channels)
        channels.map { |channel| channel.to_s.strip.to_sym }.uniq - type_definition.required_channels
      end

      def selected_optional_channels
        requested = requested_optional_channels
        candidates = type_definition.available_channels ? type_definition.optional_channels : requested

        candidates.select do |channel|
          preference_enabled?(channel, default: requested.include?(channel))
        end
      end

      def preference_enabled?(channel, default:)
        return default unless preference_table_available?

        RecordingStudioNotifications::Preference.enabled_for?(
          recipient: @recipient,
          notification_type: @notification_type,
          channel: channel,
          default: default
        )
      end

      def reject_hidden_required_in_app!
        return if inbox?
        return unless type_definition.required_channels.include?(:in_app)

        raise ArgumentError, "inbox cannot be false when in_app is a required channel"
      end

      def inbox?
        return @inbox_override unless @inbox_override.nil?

        type_definition.inbox != false
      end

      def without_hidden_in_app(channels)
        return channels if inbox?

        channels - [:in_app]
      end
    end
  end
end
