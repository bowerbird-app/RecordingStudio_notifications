# frozen_string_literal: true

module RecordingStudioNotifications
  NotificationType = Struct.new(:key, :label, :description, :default_channels, keyword_init: true)

  class NotificationTypeRegistry
    def initialize
      @types = {}
      @mutex = Mutex.new
    end

    def register(key, label:, description: nil, default_channels: nil)
      normalized_key = normalize_key!(key)
      metadata = NotificationType.new(
        key: normalized_key,
        label: label.to_s,
        description: description&.to_s,
        default_channels: Array(default_channels).presence&.map { |channel| normalize_key!(channel) }
      ).freeze

      @mutex.synchronize { @types[normalized_key] = metadata }
      metadata
    end

    def fetch(key)
      @mutex.synchronize { @types.fetch(normalize_key!(key)) }
    end

    def [](key)
      @mutex.synchronize { @types[normalize_key!(key)] }
    end

    def registered?(key)
      @mutex.synchronize { @types.key?(normalize_key!(key)) }
    rescue ArgumentError
      false
    end

    def keys
      @mutex.synchronize { @types.keys.sort_by(&:to_s) }
    end

    def clear!
      @mutex.synchronize { @types.clear }
    end

    private

    def normalize_key!(key)
      normalized = key.to_s.strip
      raise ArgumentError, "notification type is required" if normalized.blank?

      normalized.to_sym
    end
  end
end
