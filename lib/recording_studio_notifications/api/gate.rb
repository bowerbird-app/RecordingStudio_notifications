# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    module Gate
      VIEW_ROLE = :view
      FORBIDDEN_MESSAGE = "API access grant is not authorized for this capability"

      module_function

      def actor(context)
        context.access_grant.actor
      end

      def authorize_inbox!(context)
        authorize_root!(context)
        recipient = actor(context)
        forbidden! unless Services::NotificationAuthorization.allowed?(actor: recipient, recipient: recipient)

        recipient
      end

      def authorize_preferences!(context)
        authorize_root!(context)
        recipient = actor(context)
        forbidden! unless Services::NotificationAuthorization.preferences_allowed?(actor: recipient, recipient: recipient)

        recipient
      end

      def visible_notification!(context)
        recipient = authorize_inbox!(context)
        notification = Notification.for_recipient(recipient).find_by(id: param(context, :id))
        not_found! if notification.blank?
        not_found! unless notification.inbox?
        not_found! if notification.archived?
        unless Services::NotificationAuthorization.visible_notification?(
          actor: recipient,
          notification: notification
        )
          forbidden!
        end

        notification
      end

      def authorize_root!(context)
        context.access_grant.authorize!(recording: context.root_recording, role: VIEW_ROLE)
      end

      def param(context, key)
        context.params.with_indifferent_access[key]
      end

      def request_payload(context)
        context.params.with_indifferent_access
      end

      def forbidden!
        raise RecordingStudioApi::AuthorizationError, FORBIDDEN_MESSAGE
      end

      def not_found!
        raise RecordingStudioApi::NotFoundError, "Notification not found"
      end
    end
  end
end
