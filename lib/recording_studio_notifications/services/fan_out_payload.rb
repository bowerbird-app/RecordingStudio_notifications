# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    class FanOutPayload
      OPTIONS = %i[
        notification_type title body url metadata actor notifiable recording root_recording channels inbox
      ].freeze

      def self.build(recipient_scope:, idempotency_key:, **attributes)
        assert_arguments!(recipient_scope, idempotency_key, attributes)
        actor = attributes[:actor] || RecordingStudioNotifications.configuration.resolve_actor
        {
          "recipient_scope" => recipient_scope.to_s.strip,
          "idempotency_key" => idempotency_key.to_s,
          "notification_type" => attributes[:notification_type].to_s,
          "title" => attributes[:title],
          "body" => attributes[:body],
          "url" => attributes[:url],
          "metadata" => json_metadata(attributes[:metadata]),
          "channels" => json_channels(attributes[:channels]),
          "inbox" => attributes.key?(:inbox) ? cast_inbox(attributes[:inbox]) : nil,
          "actor_gid" => global_id(actor),
          "notifiable_gid" => global_id(attributes[:notifiable]),
          "recording_gid" => global_id(attributes[:recording]),
          "root_recording_gid" => global_id(attributes[:root_recording])
        }
      end

      def self.assert_arguments!(recipient_scope, idempotency_key, attributes)
        unknown = attributes.keys.map(&:to_sym) - OPTIONS
        raise ArgumentError, "unknown notify_fan_out option: #{unknown.join(', ')}" if unknown.any?
        raise ArgumentError, "idempotency_key is required" if idempotency_key.blank?

        scope = recipient_scope.to_s.strip
        raise ArgumentError, "recipient scope is required" if scope.empty?
        return if RecordingStudioNotifications.configuration.recipient_scopes.registered?(scope)

        raise ArgumentError, "recipient scope is not registered: #{scope}"
      end
      private_class_method :assert_arguments!

      def self.json_metadata(metadata)
        return {} if metadata.blank?
        raise ArgumentError, "metadata must be a Hash" unless metadata.is_a?(Hash)

        metadata.deep_stringify_keys
      end
      private_class_method :json_metadata

      def self.json_channels(channels)
        return nil if channels.nil?

        Array(channels).map { |channel| channel.to_s.strip }.reject(&:empty?)
      end
      private_class_method :json_channels

      def self.cast_inbox(value)
        return nil if value.nil?

        ActiveModel::Type::Boolean.new.cast(value)
      end
      private_class_method :cast_inbox

      def self.global_id(record)
        return if record.nil?
        return record.to_global_id.to_s if record.respond_to?(:to_global_id)

        raise ArgumentError, "fan-out actor, recording, and notifiable must be GlobalID records"
      end
      private_class_method :global_id
    end
  end
end
