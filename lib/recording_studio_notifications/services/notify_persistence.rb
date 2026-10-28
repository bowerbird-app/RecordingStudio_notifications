# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    module NotifyPersistence
      private

      def create_and_deliver!(existing)
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
            notification = existing || create_notification!
            create_deliveries!(notification) if notification.previously_new_record?
            should_deliver_immediately = notification.deliveries.pending.any? { |delivery| !delivery.deferred_rollup? }

            notification
          end
        end

        enqueue_or_deliver!(notification) if should_deliver_immediately
        notification
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
          idempotency_key: @idempotency_key,
          inbox: inbox?
        )
      rescue ActiveRecord::RecordNotUnique
        retry unless (existing = find_idempotent_notification)

        existing
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
