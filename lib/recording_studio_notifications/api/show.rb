# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    class Show
      TITLE = "Notifications - Show"
      OPENAPI = {
        title: TITLE,
        summary: TITLE,
        description: ToolDescriptions::SHOW,
        tags: ["Notifications"]
      }.freeze
      INPUT_CONTRACT = {
        reject_unknown: false,
        fields: {
          id: {
            type: :string,
            required: true,
            description: ToolDescriptions::ID
          }
        }
      }.freeze

      def self.call(context)
        Serialize.notification(Gate.visible_notification!(context))
      end
    end
  end
end
