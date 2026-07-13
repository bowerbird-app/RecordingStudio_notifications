# frozen_string_literal: true

module RecordingStudioNotifications
  class DeliveryJob < ApplicationJob
    def perform(notification_id)
      notification = Notification.find(notification_id)

      notification.deliveries.pending.find_each do |delivery|
        next if delivery.deferred_rollup?

        deliver_one(notification, delivery)
      end
    end

    private

    def deliver_one(notification, delivery)
      ActiveSupport::Notifications.instrument(
        "deliver.recording_studio_notifications",
        notification_id: notification.id,
        delivery_id: delivery.id,
        channel: delivery.channel
      ) do
        adapter = RecordingStudioNotifications.channels.fetch(delivery.channel.to_sym)
        adapter.deliver(notification: notification, delivery: delivery)
        delivery.mark_delivered! if delivery.reload.pending?
      end
    rescue StandardError => e
      delivery.mark_failed!(e) if delivery&.persisted?
      raise if RecordingStudioNotifications.configuration.raise_on_delivery_error
    end
  end
end
