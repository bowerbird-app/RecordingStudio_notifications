# frozen_string_literal: true

module RecordingStudioNotifications
  module ReplyMethods
    def reply_handlers
      @reply_handlers ||= ReplyHandlerRegistry.new
    end

    def register_reply_handler(type, &)
      reply_handlers.register(type, &)
    end

    def replyable?(type)
      reply_handlers.replyable?(type)
    end

    def reply_target(delivery_id:, channel: nil)
      Services::ReplyLookup.call(delivery_id:, channel:)
    end

    def handle_reply(...)
      Services::HandleReply.call(...)
    end
  end
end
