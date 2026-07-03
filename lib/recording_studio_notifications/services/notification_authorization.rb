# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    class NotificationAuthorization
      class NotAuthorized < StandardError; end

      VIEW_NOTIFICATIONS_ACTION = :view_notifications
      MANAGE_PREFERENCES_ACTION = :"recording_studio_notifications.manage_preferences"
      VIEW_RECORDING_ACTION = :view

      def self.allowed?(...)
        new(...).allowed?
      end

      def self.preferences_allowed?(actor:, recipient:, controller: nil)
        new(actor: actor, recipient: recipient, controller: controller, action: MANAGE_PREFERENCES_ACTION).allowed?
      end

      def self.visible_notification?(actor:, notification:, controller: nil)
        new(actor: actor, notification: notification, controller: controller).visible_notification?
      end

      def initialize(actor:, recipient: nil, notification: nil, recording: nil, controller: nil,
                     action: VIEW_NOTIFICATIONS_ACTION)
        @actor = actor
        @recipient = recipient || notification&.recipient
        @notification = notification
        @recording = recording || notification&.root_recording || notification&.recording
        @controller = controller
        @action = action
      end

      def allowed?
        return false unless @actor
        return accessible_action_allowed? if accessible_action_available?

        same_actor_and_recipient?
      end

      def visible_notification?
        return false unless same_actor_and_recipient? || allowed?
        return true unless @notification&.root_recording

        accessible_view_allowed?
      end

      private

      def same_actor_and_recipient?
        @recipient && @actor.class.name == @recipient.class.name && @actor.id.to_s == @recipient.id.to_s
      end

      def accessible_action_available?
        defined?(RecordingStudioAccessible) && RecordingStudioAccessible.respond_to?(:authorized_action?)
      end

      def accessible_action_allowed?
        RecordingStudioAccessible.authorized_action?(
          actor: @actor,
          action: @action,
          recording: @recording,
          context: { recipient: @recipient, notification: @notification },
          controller: @controller
        )
      end

      def accessible_view_allowed?
        return true unless accessible_action_available?

        RecordingStudioAccessible.authorized_action?(
          actor: @actor,
          action: VIEW_RECORDING_ACTION,
          recording: @notification.root_recording,
          context: { notification: @notification, recipient: @recipient },
          controller: @controller
        )
      end
    end
  end
end
