# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    class HandleReply
      EVENT = "reply.recording_studio_notifications"

      def self.call(...)
        new(...).call
      end

      def initialize(notification:, recipient:, body:, attachments:, channel:, idempotency_key:)
        @notification = notification
        @recipient = recipient
        @body = body
        @attachments = attachments
        @channel = channel.to_s.strip
        @idempotency_key = idempotency_key.to_s.strip
      end

      def call
        validate!
        payload = event_payload
        ActiveSupport::Notifications.instrument(EVENT, payload) do
          result = perform
          payload[:outcome] = result.outcome.to_s
          payload[:reason] = result.reason&.to_s
          result
        end
      end

      private

      def validate!
        raise ArgumentError, "notification is required" unless @notification
        raise ArgumentError, "recipient is required" unless @recipient
        raise ArgumentError, "channel is required" if @channel.empty?
        raise ArgumentError, "idempotency_key is required" if @idempotency_key.empty?
      end

      def event_payload
        {
          type: @notification.notification_type.to_s,
          channel: @channel,
          outcome: nil,
          reason: nil
        }
      end

      def perform
        refused = refusal
        return refused if refused

        claim_and_handle
      end

      def refusal
        return ReplyResult.rejected(:recipient_mismatch) unless @notification.recipient == @recipient
        return ReplyResult.rejected(:not_visible) unless visible?
        return ReplyResult.rejected(:not_replyable) unless RecordingStudioNotifications.replyable?(@notification.notification_type)

        nil
      end

      def visible?
        NotificationAuthorization.visible_for_reply?(actor: @recipient, notification: @notification)
      end

      def claim_and_handle
        state = nil
        Reply.transaction(requires_new: true) do
          state = run_claim
          raise ActiveRecord::Rollback unless state.is_a?(ReplyResult)
        end
        report(state)
      end

      def run_claim
        claimed = insert_claim
        return :duplicate if claimed == :duplicate

        result = invoke_handler
        return save_result(claimed, result) if recordable?(result)

        [:failed, :invalid_result, result.class.name]
      rescue StandardError => e
        [:failed, :handler_error, e.class.name]
      end

      def insert_claim
        Reply.transaction(requires_new: true) do
          Reply.create!(
            notification: @notification,
            channel: @channel,
            idempotency_key: @idempotency_key,
            status: "pending"
          )
        end
      rescue ActiveRecord::RecordNotUnique
        :duplicate
      end

      def invoke_handler
        handler = RecordingStudioNotifications.reply_handlers.fetch(@notification.notification_type)
        handler.call(
          notification: @notification,
          recipient: @recipient,
          body: @body,
          attachments: @attachments
        )
      end

      def recordable?(result)
        return true if result.is_a?(ReplyResult) && result.ok? && result.reason.nil?
        return true if result.is_a?(ReplyResult) && result.rejected? && result.reason.is_a?(Symbol)

        false
      end

      def save_result(claimed, result)
        claimed.update!(status: result.ok? ? "ok" : "rejected", reason: result.reason&.to_s)
        result
      end

      def report(state)
        return state if state.is_a?(ReplyResult)
        return ReplyResult.duplicate if state == :duplicate

        _marker, reason, error_class = state
        log_failure(error_class)
        ReplyResult.failed(reason)
      end

      def log_failure(error_class)
        Rails.logger.error("RecordingStudioNotifications reply failed: #{error_class}")
      end
    end
  end
end
