# frozen_string_literal: true

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
        @channels = channels
        @idempotency_key = idempotency_key.presence
        @deliver_later = deliver_later
      end

      def call
        validate_inputs!

        Notification.transaction do
          notification = find_idempotent_notification || create_notification!
          create_deliveries!(notification)
          enqueue_or_deliver!(notification) if notification.previously_new_record? || notification.deliveries.pending.exists?
          notification
        end
      end

      private

      def validate_inputs!
        raise ArgumentError, "recipient is required" unless @recipient
        raise ArgumentError, "title is required" if @title.to_s.blank?
        raise ArgumentError, "notification_type is not registered" unless type_definition
        raise ArgumentError, "at least one channel is required" if channel_keys.empty?

        unregistered_channel = channel_keys.find { |channel| !RecordingStudioNotifications.channels.registered?(channel) }
        raise ArgumentError, "channel is not registered: #{unregistered_channel}" if unregistered_channel

        UrlSafety.sanitize!(@url)
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
          recording: @recording,
          root_recording: resolved_root_recording,
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
          end
        end
      end

      def channel_keys
        Array(@channels || type_definition.default_channels || RecordingStudioNotifications.configuration.default_channels)
          .map { |channel| channel.to_s.strip.to_sym }
          .uniq
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
