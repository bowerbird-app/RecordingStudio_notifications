# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    class Inbox
      TITLE = "Notifications - Inbox"
      OPENAPI = {
        title: TITLE,
        summary: TITLE,
        description: ToolDescriptions::INBOX,
        tags: ["Notifications"],
        parameters: [
          {
            name: "page",
            in: "query",
            required: false,
            description: ToolDescriptions::PAGE,
            schema: { type: "integer" }
          },
          {
            name: "per_page",
            in: "query",
            required: false,
            description: ToolDescriptions::PER_PAGE,
            schema: { type: "integer" }
          }
        ]
      }.freeze
      INPUT_CONTRACT = {
        reject_unknown: false,
        fields: {
          page: {
            type: :integer,
            required: false,
            description: ToolDescriptions::PAGE
          },
          per_page: {
            type: :integer,
            required: false,
            description: ToolDescriptions::PER_PAGE
          }
        }
      }.freeze

      def self.call(context)
        recipient = Gate.authorize_inbox!(context)
        inbox = Services::InboxScope.relation(
          recipient: recipient,
          actor: recipient,
          root_recording: context.root_recording,
          inbox_scope: "current_root"
        )
        unless Services::InboxScope.authorized_root_recording_ids_supported?
          inbox = inbox.select do |notification|
            Services::NotificationAuthorization.visible_notification?(
              actor: recipient,
              notification: notification
            )
          end
        end
        payload = Gate.request_payload(context)
        page = Query.paginate(
          inbox,
          page: payload[:page],
          per_page: payload[:per_page]
        )
        {
          records: page.fetch(:rows).map { |notification| Serialize.notification(notification) },
          meta: page.fetch(:meta)
        }
      end
    end
  end
end
