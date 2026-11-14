# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    # Channel list for one fan-out recipient, using preferences already loaded for the chunk.
    class FanOutChannels
      def initialize(type:, requested_channels:, inbox:, preference_channels:, recipient:)
        @type = type
        @requested_channels = requested_channels
        @inbox = inbox
        @preference_channels = preference_channels || {}
        @recipient = recipient
      end

      def keys
        selected = without_hidden_in_app(deliverable_channels)
        return [] unless required_channels.all? { |channel| selected.include?(channel) }

        selected
      end

      private

      def required_channels
        @type.required_channels
      end

      def deliverable_channels
        enabled_channels.select { |channel| applicable?(channel) }
      end

      def enabled_channels
        (selected_optional_channels + required_channels).uniq.select do |channel|
          required_channels.include?(channel) || preference_enabled?(channel, default: true)
        end
      end

      def selected_optional_channels
        requested = requested_optional_channels
        candidates = @type.available_channels ? @type.optional_channels : requested
        candidates.select { |channel| preference_enabled?(channel, default: requested.include?(channel)) }
      end

      def requested_optional_channels
        source = @requested_channels
        source = @type.default_channels if source.nil?
        source = RecordingStudioNotifications.configuration.default_channels if source.nil?
        Array(source).map { |channel| channel.to_s.strip.to_sym }.uniq - required_channels
      end

      def preference_enabled?(channel, default:)
        return default unless @preference_channels.key?(channel)

        @preference_channels[channel]
      end

      def applicable?(channel)
        adapter = RecordingStudioNotifications.channels.fetch(channel)
        return true unless adapter.respond_to?(:available_for?)

        adapter.available_for?(recipient: @recipient, notification: nil, delivery: nil)
      end

      def without_hidden_in_app(channels)
        return channels if @inbox

        channels - [:in_app]
      end
    end
  end
end
