# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    class Inbox
      TITLE = "Notifications - Inbox"
      OPENAPI = {
        title: TITLE,
        summary: TITLE,
        description: "Paged inbox for the current Accessible actor. Uses the HTML inbox scopes " \
                     "Notification.for_recipient.active.visible_in_inbox.in_inbox. Root view is " \
                     "authorized_root_recording_ids(actor:, role: :view) when " \
                     "authorized_root_recording_ids_supported? is true, and visible_notification? " \
                     "otherwise. Offset paging with page and per_page. The query uses LIMIT and OFFSET.",
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
        inbox = Services::InboxScope.relation(recipient: recipient, actor: recipient)
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
