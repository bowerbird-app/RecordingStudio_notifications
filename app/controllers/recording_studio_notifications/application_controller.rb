# frozen_string_literal: true

module RecordingStudioNotifications
  parent_controller = defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base

  class ApplicationController < parent_controller
    include ::RecordingStudio::RootSwitchable::ControllerSupport if defined?(::RecordingStudio::RootSwitchable::ControllerSupport)

    protect_from_forgery with: :exception

    helper_method :current_notifications_actor, :current_notifications_root_recording

    private

    def current_notifications_actor
      actor = current_user if respond_to?(:current_user, true)
      actor || RecordingStudioNotifications.configuration.resolve_actor
    end

    def current_notifications_root_recording
      @current_notifications_root_recording ||= RecordingStudioNotifications.configuration.resolve_current_root(controller: self)
    end

    def authorize_notifications!(recipient:, notification: nil, recording: nil)
      return true if Services::NotificationAuthorization.allowed?(
        actor: current_notifications_actor,
        recipient: recipient,
        notification: notification,
        recording: recording,
        controller: self
      )

      head :forbidden
      false
    end

    def authorize_preferences!(recipient:)
      return true if Services::NotificationAuthorization.preferences_allowed?(
        actor: current_notifications_actor,
        recipient: recipient,
        controller: self
      )

      head :forbidden
      false
    end
  end
end
