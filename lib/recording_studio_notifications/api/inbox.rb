# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    class Inbox
      TITLE = "Notifications - Inbox"
      OPENAPI = {
        title: TITLE,
        summary: TITLE,
        description: "Paged inbox for the current Accessible actor. Uses Notification.for_recipient " \
                     "and visible_notification? under :view_notifications. Offset paging with page " \
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
            description: "Rows per page. Defaults to #{Query::DEFAULT_PER_PAGE}, max #{Query::MAX_PER_PAGE}.",
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
            description: "Rows per page. Defaults to #{Query::DEFAULT_PER_PAGE}, max #{Query::MAX_PER_PAGE}."
          }
        }
      }.freeze

      def self.call(context)
        recipient = Gate.authorize_inbox!(context)
        visible = Notification.for_recipient(recipient).newest_first.select do |notification|
          Services::NotificationAuthorization.visible_notification?(
            actor: recipient,
            notification: notification
          )
        end
        page = Query.paginate(
          visible,
          page: Gate.param(context, :page),
          per_page: Gate.param(context, :per_page)
        )
        {
          records: page.fetch(:rows).map { |notification| Serialize.notification(notification) },
          meta: page.fetch(:meta)
        }
      end
    end
  end
end
