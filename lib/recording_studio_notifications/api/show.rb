# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    class Show
      TITLE = "Notifications - Show"
      OPENAPI = {
        title: TITLE,
        summary: TITLE,
        description: "One notification for the current actor. Looks up Notification.for_recipient, " \
                     "requires inbox? like HTML show, then visible_notification? under " \
                     ":view_notifications. Missing, archived, and inbox: false rows are 404. " \
                     "A row the actor cannot see is 403.",
        tags: ["Notifications"]
      }.freeze
      INPUT_CONTRACT = {
        reject_unknown: false,
        fields: {
          id: {
            type: :string,
            required: true,
            description: "Notification id."
          }
        }
      }.freeze

      def self.call(context)
        Serialize.notification(Gate.visible_notification!(context))
      end
    end
  end
end
