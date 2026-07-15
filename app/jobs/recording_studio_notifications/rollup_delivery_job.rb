# frozen_string_literal: true

require "time"

module RecordingStudioNotifications
  class RollupDeliveryJob < ApplicationJob
    def perform(now: Time.current)
      return unless RecordingStudioNotifications.configuration.rollup_delivery_enabled

      release_stale_reservations!(now)

      eligible_rollup_keys(now).each do |rollup_key|
        deliveries = reserve_rollup!(rollup_key, now)
        deliver_rollup!(deliveries) if deliveries.any?
      end
    end

    private

    def eligible_rollup_keys(now)
      Delivery.retryable_rollups.find_each.filter_map do |delivery|
        rollup_key = delivery.metadata["rollup_key"]
        rollup_key if rollup_key.present? && period_closed?(delivery, now)
      end.uniq
    end

    def reserve_rollup!(rollup_key, now)
      Delivery.transaction do
        deliveries = Delivery.retryable_rollups
                             .where("metadata ->> 'rollup_key' = ?", rollup_key)
                             .lock
                             .to_a
                             .select { |delivery| period_closed?(delivery, now) }
        return [] if deliveries.empty?

        deliveries.each { |delivery| delivery.reserve_rollup!(at: now) }
        deliveries
      end
    end

    def deliver_rollup!(deliveries)
      first_delivery = deliveries.first
      notifications = deliveries.map(&:notification)
      metadata = first_delivery.metadata
      adapter = RecordingStudioNotifications.channels.fetch(first_delivery.channel.to_sym)

      raise ArgumentError, "channel #{first_delivery.channel.inspect} does not support rollup delivery" unless adapter.respond_to?(:deliver_rollup)

      ActiveSupport::Notifications.instrument(
        "deliver_rollup.recording_studio_notifications",
        rollup_key: metadata.fetch("rollup_key"),
        channel: first_delivery.channel,
        delivery_ids: deliveries.map(&:id)
      ) do
        adapter.deliver_rollup(
          notifications: notifications,
          deliveries: deliveries,
          rollup_key: metadata.fetch("rollup_key"),
          cadence: metadata.fetch("cadence").to_sym,
          period_starts_at: Time.iso8601(metadata.fetch("period_starts_at")),
          period_ends_at: Time.iso8601(metadata.fetch("period_ends_at")),
          idempotency_key: metadata.fetch("rollup_key")
        )
      end

      Delivery.transaction { deliveries.each(&:mark_delivered!) }
    rescue StandardError => e
      Delivery.transaction { deliveries.each { |delivery| delivery.mark_failed!(e) } } if deliveries
      raise if RecordingStudioNotifications.configuration.raise_on_delivery_error
    end

    def release_stale_reservations!(now)
      timeout = RecordingStudioNotifications.configuration.rollup_reservation_timeout
      Delivery.rollups.processing.where("rollup_reserved_at < ?", now - timeout).find_each do |delivery|
        delivery.update!(status: "pending", rollup_reserved_at: nil)
      end
    end

    def period_closed?(delivery, now)
      Time.iso8601(delivery.metadata.fetch("period_ends_at")) <= now
    rescue ArgumentError, KeyError
      false
    end
  end
end
