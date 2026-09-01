# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    module ChannelApplicability
      def channel_applicable?(channel)
        adapter = RecordingStudioNotifications.channels.fetch(channel)
        return true unless adapter.respond_to?(:available_for?)

        adapter.available_for?(recipient: @recipient, notification: nil, delivery: nil)
      end

      def validate_required_channels_available!(channel_keys)
        inapplicable_required = type_definition.required_channels.find do |channel|
          channel_keys.include?(channel) && !channel_applicable?(channel)
        end
        return unless inapplicable_required

        raise ArgumentError, "required channel is not available for recipient: #{inapplicable_required}"
      end
    end
  end
end
