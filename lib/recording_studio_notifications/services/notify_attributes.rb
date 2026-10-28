# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    module NotifyAttributes
      CALL_KEYS = %i[
        notification_type recipient title body url metadata actor notifiable recording
        root_recording channels idempotency_key deliver_later inbox
      ].freeze
      REQUIRED_KEYS = %i[notification_type recipient title].freeze

      private

      def apply_notify_attributes(attributes)
        reject_unknown_notify_keys!(attributes)
        require_notify_keys!(attributes)

        @notification_type = attributes.fetch(:notification_type).to_s
        @recipient = attributes.fetch(:recipient)
        @title = attributes.fetch(:title)
        @body = attributes[:body]
        @url = attributes[:url]
        @metadata = attributes[:metadata].presence || {}
        @actor = attributes[:actor] || RecordingStudioNotifications.configuration.resolve_actor
        @notifiable = attributes[:notifiable]
        @recording = attributes[:recording]
        @root_recording = attributes[:root_recording]
        @requested_channels = attributes[:channels]
        @idempotency_key = attributes[:idempotency_key].presence
        @deliver_later = attributes[:deliver_later]
        inbox = attributes[:inbox]
        @inbox_override = inbox.nil? ? nil : ActiveModel::Type::Boolean.new.cast(inbox)
      end

      def reject_unknown_notify_keys!(attributes)
        unknown = attributes.keys - CALL_KEYS
        return if unknown.empty?

        label = unknown.one? ? "unknown keyword" : "unknown keywords"
        raise ArgumentError, "#{label}: #{unknown.join(', ')}"
      end

      def require_notify_keys!(attributes)
        missing = REQUIRED_KEYS.reject { |key| attributes.key?(key) }
        return if missing.empty?

        label = missing.one? ? "missing keyword" : "missing keywords"
        raise ArgumentError, "#{label}: #{missing.map(&:inspect).join(', ')}"
      end
    end
  end
end
