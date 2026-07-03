# frozen_string_literal: true

module RecordingStudioNotifications
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    helper_method :current_notifications_actor

    private

    def current_notifications_actor
      if respond_to?(:current_user, true)
        current_user
      else
        RecordingStudioNotifications.configuration.resolve_actor
      end
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
  end
end
