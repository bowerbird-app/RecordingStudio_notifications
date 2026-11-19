# frozen_string_literal: true

module RecordingStudioNotifications
  class ReplyResult
    attr_reader :outcome, :reason

    def self.ok
      new(:ok)
    end

    def self.rejected(reason)
      new(:rejected, symbol_reason!(reason))
    end

    def self.duplicate
      new(:duplicate)
    end

    def self.failed(reason)
      new(:failed, symbol_reason!(reason))
    end

    def self.symbol_reason!(reason)
      return reason if reason.is_a?(Symbol)

      raise ArgumentError, "reason must be a symbol"
    end
    private_class_method :symbol_reason!

    def initialize(outcome, reason = nil)
      @outcome = outcome
      @reason = reason
      freeze
    end

    def ok?
      outcome == :ok
    end

    def rejected?
      outcome == :rejected
    end

    def duplicate?
      outcome == :duplicate
    end

    def failed?
      outcome == :failed
    end
  end
end
