# frozen_string_literal: true

module RecordingStudioNotifications
  class DeliveryJob < ApplicationJob
    def perform(notification_id)
      notification = Notification.find(notification_id)

      notification.deliveries.pending.find_each do |delivery|
        deliver_one(notification, delivery)
      end
    end

    private

    def deliver_one(notification, delivery)
      adapter = RecordingStudioNotifications.channels.fetch(delivery.channel.to_sym)
      adapter.deliver(notification: notification, delivery: delivery)
    rescue StandardError => e
      delivery.mark_failed!(e.message) if delivery&.persisted?
      raise if RecordingStudioNotifications.configuration.raise_on_delivery_error
    end
  end
end
