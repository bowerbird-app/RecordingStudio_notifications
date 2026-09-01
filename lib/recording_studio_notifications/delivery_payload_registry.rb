# frozen_string_literal: true

module RecordingStudioNotifications
  class DeliveryPayloadError < StandardError; end

  DeliveryPayload = Struct.new(:title, :body, :url, keyword_init: true)

  class DeliveryPayloadRegistry
    def initialize
      @resolvers = {}
      @mutex = Mutex.new
    end

    def register(type, &block)
      normalized = normalize_key!(type)
      raise ArgumentError, "resolver block is required" unless block

      @mutex.synchronize { @resolvers[normalized] = block }
      block
    end

    def resolve(notification:, delivery:)
      type = notification.notification_type.to_s
      resolver = @mutex.synchronize { @resolvers[type.to_sym] }
      return unless resolver

      resolver.call(notification: notification, delivery: delivery)
    end

    def registered?(type)
      @mutex.synchronize { @resolvers.key?(normalize_key!(type)) }
    rescue ArgumentError
      false
    end

    def clear!
      @mutex.synchronize { @resolvers.clear }
    end

    private

    def normalize_key!(key)
      normalized = key.to_s.strip
      raise ArgumentError, "notification type is required" if normalized.blank?

      normalized.to_sym
    end
  end
end
