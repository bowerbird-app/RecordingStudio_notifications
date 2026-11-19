# frozen_string_literal: true

module RecordingStudioNotifications
  ReplyTarget = Struct.new(:notification, :recipient, keyword_init: true)

  module Services
    class ReplyLookup
      UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      def self.call(delivery_id:)
        id = delivery_id.to_s
        return unless id.match?(UUID)

        delivery = Delivery.find_by(id: id)
        notification = delivery&.notification
        return unless notification

        ReplyTarget.new(notification: notification, recipient: notification.recipient)
      end
    end
  end
end
