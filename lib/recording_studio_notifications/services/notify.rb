# frozen_string_literal: true

require_relative "cadence_period"

module RecordingStudioNotifications
  module Services
    class Notify
      def self.call(...)
        new(...).call
      end

      def initialize(notification_type:, recipient:, title:, body: nil, url: nil, metadata: {}, actor: nil,
                     notifiable: nil, recording: nil, root_recording: nil, channels: nil, idempotency_key: nil,
                     deliver_later: nil)
        @notification_type = notification_type.to_s
        @recipient = recipient
        @title = title
        @body = body
        @url = url
        @metadata = metadata.presence || {}
        @actor = actor || RecordingStudioNotifications.configuration.resolve_actor
        @notifiable = notifiable
        @recording = recording
        @root_recording = root_recording
        @requested_channels = channels
        @idempotency_key = idempotency_key.presence
        @deliver_later = deliver_later
      end

      def call
        validate_inputs!
        authorize_creation!

        hooks.run(:before_service, self.class, service_payload)
        result = hooks.run_around(:around_service, self) { create_and_deliver! }
        hooks.run(:after_service, self.class, result)
        result
      end

      private

      def create_and_deliver!
        notification = nil
        should_deliver_immediately = false

        ActiveSupport::Notifications.instrument(
          "notify.recording_studio_notifications",
          notification_type: @notification_type,
          recipient: @recipient,
          channels: channel_keys,
          root_recording_id: resolved_root_recording&.id
        ) do
          Notification.transaction do
            notification = find_idempotent_notification || create_notification!
            create_deliveries!(notification)
            should_deliver_immediately = notification.deliveries.pending.any? { |delivery| !delivery.deferred_rollup? }

            notification
          end
        end

        enqueue_or_deliver!(notification) if should_deliver_immediately
        notification
      end

      def validate_inputs!
        raise ArgumentError, "recipient is required" unless @recipient
        raise ArgumentError, "title is required" if @title.to_s.blank?
        raise ArgumentError, "notification_type is not registered" unless type_definition

        if type_definition.scope == :root && resolved_root_recording.blank?
          raise ArgumentError,
                "root_recording is required"
        end
        raise ArgumentError, "root_recording does not match recording or notifiable" unless consistent_root_scope?
        raise ArgumentError, "at least one channel is required" if channel_keys.empty?

        unregistered_channel = channel_keys.find do |channel|
          !RecordingStudioNotifications.channels.registered?(channel)
        end
        raise ArgumentError, "channel is not registered: #{unregistered_channel}" if unregistered_channel

        if type_definition.available_channels
          unavailable_channel = channel_keys.find { |channel| !type_definition.available_channels.include?(channel) }
          if unavailable_channel
            raise ArgumentError,
                  "channel is not available for #{@notification_type}: #{unavailable_channel}"
          end
        end

        unsupported_rollup_channel = channel_keys.find do |channel|
          deferred_rollup_channel?(channel) && !RecordingStudioNotifications.channels.fetch(channel).respond_to?(:deliver_rollup)
        end
        if unsupported_rollup_channel
          raise ArgumentError, "channel does not support grouped delivery: #{unsupported_rollup_channel}"
        end

        UrlSafety.sanitize!(@url)
      end

      def authorize_creation!
        return unless type_definition.creation_action
        return if accessible_action_allowed?(type_definition.creation_action)

        raise RecordingStudioNotifications::Services::NotificationAuthorization::NotAuthorized,
              "not authorized to create #{@notification_type} notifications"
      end

      def accessible_action_allowed?(action)
        return false unless defined?(RecordingStudioAccessible)
        return false unless RecordingStudioAccessible.respond_to?(:authorized_action?)

        RecordingStudioAccessible.authorized_action?(
          actor: @actor,
          action: action,
          recording: resolved_root_recording || @recording,
          context: {
            recipient: @recipient,
            notification_type: @notification_type.to_sym,
            notifiable: @notifiable,
            metadata: @metadata
          }
        )
      end

      def hooks
        RecordingStudioNotifications.configuration.hooks
      end

      def service_payload
        {
          notification_type: @notification_type,
          recipient: @recipient,
          actor: @actor,
          notifiable: @notifiable,
          recording: @recording,
          root_recording: resolved_root_recording,
          channels: channel_keys
        }
      end

      def type_definition
        @type_definition ||= RecordingStudioNotifications.notification_types[@notification_type]
      end

      def find_idempotent_notification
        return if @idempotency_key.blank?

        Notification.find_by(recipient: @recipient, idempotency_key: @idempotency_key)
      end

      def create_notification!
        Notification.create!(
          notification_type: @notification_type,
          recipient: @recipient,
          actor: @actor,
          notifiable: @notifiable,
          recording: type_definition.scope == :global ? nil : @recording,
          root_recording: type_definition.scope == :global ? nil : resolved_root_recording,
          title: @title,
          body: @body,
          url: @url,
          metadata: @metadata,
          idempotency_key: @idempotency_key
        )
      rescue ActiveRecord::RecordNotUnique
        retry unless (existing = find_idempotent_notification)

        existing
      end

      def resolved_root_recording
        return nil if type_definition&.scope == :global

        @resolved_root_recording ||= RootResolver.call(
          root_recording: @root_recording,
          recording: @recording,
          recordable: @notifiable
        )
      end

      def create_deliveries!(notification)
        channel_keys.each do |channel|
          notification.deliveries.find_or_create_by!(channel: channel.to_s) do |delivery|
            delivery.status = "pending"
            delivery.metadata = rollup_metadata_for(notification, channel) || {}
          end
        end
      end

      def rollup_metadata_for(notification, channel)
        return unless deferred_rollup_channel?(channel)

        period = CadencePeriod.for(
          timestamp: notification.created_at,
          cadence: effective_cadence,
          time_zone: recipient_time_zone
        )
        starts_at = period.starts_at.utc.iso8601

        {
          "rollup" => true,
          "rollup_key" => [
            "#{@recipient.class.name}:#{@recipient.id}",
            @notification_type,
            channel,
            effective_cadence,
            starts_at
          ].join("/"),
          "cadence" => effective_cadence.to_s,
          "period_starts_at" => starts_at,
          "period_ends_at" => period.ends_at.utc.iso8601
        }
      end

      def deferred_rollup_channel?(channel)
        effective_cadence != :individual && channel.to_sym != :in_app
      end

      def effective_cadence
        @effective_cadence ||= begin
          return :individual unless RecordingStudioNotifications.configuration.rollup_delivery_enabled
          return type_definition.required_cadence if type_definition.required_cadence
          return type_definition.default_cadence unless preference_table_available?

          Preference.cadence_for(
            recipient: @recipient,
            notification_type: @notification_type,
            default: type_definition.default_cadence
          )
        end
      end

      def recipient_time_zone
        @recipient.try(:time_zone).presence || Time.zone || "UTC"
      end

      def preference_table_available?
        defined?(RecordingStudioNotifications::Preference) && RecordingStudioNotifications::Preference.table_exists?
      end

      def channel_keys
        @channel_keys ||= begin
          required = type_definition.required_channels
          optional = selected_optional_channels
          selected = (optional + required).uniq
          selected.select { |channel| required.include?(channel) || preference_enabled?(channel, default: true) }
        end
      end

      def requested_optional_channels
        channels = Array(@requested_channels || type_definition.default_channels || RecordingStudioNotifications.configuration.default_channels)
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

      def consistent_root_scope?
        return true if type_definition.scope == :global

        RootResolver.consistent?(
          root_recording: resolved_root_recording,
          recording: @recording,
          recordable: @notifiable
        )
      end

      def enqueue_or_deliver!(notification)
        if deliver_later?
          DeliveryJob.perform_later(notification.id)
        else
          DeliveryJob.perform_now(notification.id)
        end
      end

      def deliver_later?
        @deliver_later.nil? ? RecordingStudioNotifications.configuration.deliver_later : @deliver_later
      end
    end
  end
end
