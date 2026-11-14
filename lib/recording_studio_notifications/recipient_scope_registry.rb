# frozen_string_literal: true

module RecordingStudioNotifications
  class RecipientScopeRegistry
    Context = Struct.new(:actor, :recording, :notifiable, :root_recording, keyword_init: true)

    def initialize
      @scopes = {}
      @mutex = Mutex.new
    end

    def register(name, handler = nil, &block)
      callable = handler || block
      key = normalize!(name)
      raise ArgumentError, "recipient scope needs a callable" unless callable

      @mutex.synchronize { @scopes[key] = callable }
      callable
    end

    def registered?(name)
      key = normalize!(name)
      @mutex.synchronize { @scopes.key?(key) }
    rescue ArgumentError
      false
    end

    def resolve(name, context)
      callable = @mutex.synchronize { @scopes.fetch(normalize!(name)) }
      callable.arity.zero? ? callable.call : callable.call(context)
    rescue KeyError
      raise ArgumentError, "recipient scope is not registered: #{name}"
    end

    private

    def normalize!(name)
      normalized = name.to_s.strip
      raise ArgumentError, "recipient scope is required" if normalized.empty?

      normalized.to_sym
    end
  end
end
