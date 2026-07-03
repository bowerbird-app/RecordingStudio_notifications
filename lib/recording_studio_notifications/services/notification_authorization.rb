# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    class NotificationAuthorization
      ACTION = :view_notifications

      def self.allowed?(...)
        new(...).allowed?
      end

      def initialize(actor:, recipient: nil, notification: nil, recording: nil, controller: nil)
        @actor = actor
        @recipient = recipient || notification&.recipient
        @notification = notification
        @recording = recording || notification&.root_recording || notification&.recording
        @controller = controller
      end

      def allowed?
        return false unless @actor
        return true if same_actor_and_recipient?
        return accessible_action_allowed? if defined?(RecordingStudioAccessible)

        false
      end

      private

      def same_actor_and_recipient?
        @recipient && @actor.class.name == @recipient.class.name && @actor.id.to_s == @recipient.id.to_s
      end

      def accessible_action_allowed?
        return false unless RecordingStudioAccessible.respond_to?(:authorized_action?)

        RecordingStudioAccessible.authorized_action?(
          actor: @actor,
          action: ACTION,
          recording: @recording,
          context: { recipient: @recipient, notification: @notification },
          controller: @controller
        )
      end
    end
  end
end
