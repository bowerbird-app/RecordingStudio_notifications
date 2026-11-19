# frozen_string_literal: true

module RecordingStudioNotifications
  ReplyTarget = Struct.new(:notification, :recipient, keyword_init: true)

  module Services
    class ReplyLookup
      UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      def self.call(delivery_id:, channel: nil)
        id = delivery_id.to_s
        return unless id.match?(UUID)

        name = channel_name(channel)
        return if !channel.nil? && name.nil?

        attributes = { id: id }
        attributes[:channel] = name if name
        delivery = Delivery.find_by(attributes)
        notification = delivery&.notification
        return unless notification

        ReplyTarget.new(notification: notification, recipient: notification.recipient)
      end

      def self.channel_name(channel)
        return if channel.nil?

        channel.to_s.strip.presence
      end
      private_class_method :channel_name
    end
  end
end
