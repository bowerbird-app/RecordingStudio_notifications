# frozen_string_literal: true

module RecordingStudioNotifications
  module FanOutMethods
    def notify_fan_out(...)
      Services::FanOut.enqueue(...)
    end

    def register_recipient_scope(...)
      configuration.recipient_scopes.register(...)
    end
  end
end
