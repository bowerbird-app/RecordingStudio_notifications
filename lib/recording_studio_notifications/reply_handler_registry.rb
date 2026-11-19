# frozen_string_literal: true

module RecordingStudioNotifications
  class ReplyHandlerRegistry
    def initialize
      @handlers = {}
      @mutex = Mutex.new
    end

    def register(type, &block)
      key = normalize_key!(type)
      raise ArgumentError, "reply handler block is required" unless block

      @mutex.synchronize { @handlers[key] = block }
      block
    end

    def fetch(type)
      key = normalize_key!(type)
      @mutex.synchronize { @handlers[key] }
    end

    def replyable?(type)
      key = normalize_key!(type)
      @mutex.synchronize { @handlers.key?(key) }
    rescue ArgumentError
      false
    end

    def clear!
      @mutex.synchronize { @handlers.clear }
    end

    private

    def normalize_key!(key)
      normalized = key.to_s.strip
      raise ArgumentError, "notification type is required" if normalized.empty?

      normalized.to_sym
    end
  end
end
