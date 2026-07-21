# frozen_string_literal: true

module RecordingStudioNotifications
  class ChannelRegistry
    def initialize
      @channels = {}
      @mutex = Mutex.new
    end

    def register(key, adapter)
      normalized_key = normalize_key!(key)
      raise ArgumentError, "channel adapter must respond to deliver" unless adapter.respond_to?(:deliver)

      @mutex.synchronize { @channels[normalized_key] = adapter }
      adapter
    end

    def fetch(key)
      @mutex.synchronize { @channels.fetch(normalize_key!(key)) }
    end

    def registered?(key)
      @mutex.synchronize { @channels.key?(normalize_key!(key)) }
    rescue ArgumentError
      false
    end

    def keys
      @mutex.synchronize { @channels.keys.sort_by(&:to_s) }
    end

    def clear!
      @mutex.synchronize { @channels.clear }
    end

    private

    def normalize_key!(key)
      normalized = key.to_s.strip
      raise ArgumentError, "channel is required" if normalized.blank?

      normalized.to_sym
    end
  end

  module Channels
    class InAppAdapter
      def deliver(notification:, delivery:)
        delivery.mark_delivered!
        notification
      end

      def deliver_rollup(notifications:, deliveries:, rollup_key:, cadence:, period_starts_at:, period_ends_at:,
                         idempotency_key:)
        notifications
      end
    end
  end
end
