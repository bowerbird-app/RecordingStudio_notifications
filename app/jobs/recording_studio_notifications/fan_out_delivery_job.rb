# frozen_string_literal: true

module RecordingStudioNotifications
  class FanOutDeliveryJob < ApplicationJob
    def perform(delivery_ids)
      Delivery.where(id: Array(delivery_ids)).includes(:notification).find_each do |delivery|
        next unless delivery.pending?
        next if delivery.deferred_rollup?

        DeliveryJob.deliver_one(delivery.notification, delivery)
      end
    end
  end
end
