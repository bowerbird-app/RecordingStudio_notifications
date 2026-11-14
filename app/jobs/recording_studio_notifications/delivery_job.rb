# frozen_string_literal: true

module RecordingStudioNotifications
  class DeliveryJob < ApplicationJob
    def self.deliver_one(notification, delivery)
      return unless claim_pending!(delivery)

      ActiveSupport::Notifications.instrument(
        "deliver.recording_studio_notifications",
        notification_id: notification.id,
        delivery_id: delivery.id,
        channel: delivery.channel
      ) do
        adapter = RecordingStudioNotifications.channels.fetch(delivery.channel.to_sym)
        adapter.deliver(notification: notification, delivery: delivery)
        current = delivery.reload
        delivery.mark_delivered! if current.pending? || current.processing?
      end
    rescue StandardError => e
      delivery.mark_failed!(e) if delivery&.persisted?
      raise if RecordingStudioNotifications.configuration.raise_on_delivery_error
    end

    def self.claim_pending!(delivery)
      return if delivery.deferred_rollup?
      return unless delivery.pending?

      claimed = Delivery.where(id: delivery.id, status: "pending")
                        .where("#{Delivery.table_name}.metadata ->> 'rollup' IS DISTINCT FROM ?", "true")
                        .update_all(status: "processing", updated_at: Time.current)
      return if claimed != 1

      delivery
    end
    private_class_method :claim_pending!

    def perform(notification_id)
      notification = Notification.find(notification_id)

      notification.deliveries.pending.find_each do |delivery|
        next if delivery.deferred_rollup?

        self.class.deliver_one(notification, delivery)
      end
    end
  end
end
