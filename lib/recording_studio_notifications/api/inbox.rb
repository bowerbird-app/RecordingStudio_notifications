# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    class Inbox
      TITLE = "Notifications - Inbox"
      OPENAPI = {
        title: TITLE,
        summary: TITLE,
        description: "Paged inbox for the current Accessible actor. Uses the HTML inbox scopes " \
                     "Notification.for_recipient.active.visible_in_inbox.in_inbox and " \
                     "visible_notification? under :view_notifications. Offset paging with page " \
                     "and per_page, same as other non-recording gem lists.",
        tags: ["Notifications"],
        parameters: [
          {
            name: "page",
            in: "query",
            required: false,
            description: "Offset page. Defaults to 1.",
            schema: { type: "integer" }
          },
          {
            name: "per_page",
            in: "query",
            required: false,
            description: "Rows per page. Same default and cap as the HTML inbox.",
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
            description: "Offset page. Defaults to 1."
          },
          per_page: {
            type: :integer,
            required: false,
            description: "Rows per page. Same default and cap as the HTML inbox."
          }
        }
      }.freeze

      def self.call(context)
        recipient = Gate.authorize_inbox!(context)
        inbox = Notification.for_recipient(recipient).active.visible_in_inbox.in_inbox.newest_first
        visible = inbox.select do |notification|
          Services::NotificationAuthorization.visible_notification?(
            actor: recipient,
            notification: notification
          )
        end
        payload = Gate.request_payload(context)
        page = Query.paginate(
          visible,
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
