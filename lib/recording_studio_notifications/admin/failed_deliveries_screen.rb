# frozen_string_literal: true

return unless defined?(RecordingStudioAdmin)

module RecordingStudioNotifications
  module Admin
    class FailedDeliveriesScreen < RecordingStudioAdmin::Screen
      key FailedDeliveriesChart::SCREEN_KEY
      icon :bell
      blast_radius :site
      title { Copy.t("admin.failed_deliveries.title", default: "Failed deliveries") }
      subtitle { Copy.t("admin.failed_deliveries.subtitle", default: "Sends that are still failed") }

      query do |_context|
        RecordingStudioNotifications::Delivery
          .failed
          .includes(notification: :recipient)
      end

      filter_presentation :inline
      filter :date_range, field: "recording_studio_notifications_deliveries.updated_at", default: :last_30_days
      filter :group_by, values: %i[hour day week month year], default: :day
      filter :channel,
             field: :channel,
             options: -> { RecordingStudioNotifications.channels.keys.map(&:to_s) }
      filter :kind, apply: lambda { |relation, value, context|
        FailedDeliveriesScreen.filter_kind(relation, value, context)
      }, options: -> { RecordingStudioNotifications.notification_types.keys.map(&:to_s) }

      summary do
        label ->(_context) { Copy.t("admin.failed_deliveries.summary", default: "Failed") }
        change_good_when :down
      end

      chart do
        title { Copy.t("admin.failed_deliveries.title", default: "Failed deliveries") }
        type :line
        series { |context| FailedDeliveriesChart.screen_series(context) }
      end

      table do
        column :updated_at, title: "Time"
        column :recipient,
               title: "Recipient",
               sortable: false,
               value: ->(row, _context) { FailedDeliveriesScreen.recipient_label_for(row) }
        column :channel, title: "Channel"
        column :error_message,
               title: "Error",
               sortable: false,
               value: ->(row, _context) { FailedDeliveriesScreen.error_label_for(row) }

        default_sort :updated_at, direction: :desc
        paginate per_page: 50
      end

      class << self
        def filter_kind(relation, value, _context)
          return relation if value.blank?

          relation.joins(:notification).where(
            RecordingStudioNotifications::Notification.table_name => { notification_type: value }
          )
        end

        def recipient_label_for(row)
          notification = row.notification
          return Copy.t("admin.failed_deliveries.recipient.none", default: "-") unless notification

          recipient = notification.recipient
          email = recipient.email if recipient.respond_to?(:email)
          return email if email.present?

          return Copy.t("admin.failed_deliveries.recipient.none", default: "-") if notification.recipient_id.blank?

          "#{notification.recipient_type} ##{notification.recipient_id}"
        end

        def error_label_for(row)
          row.error_message.presence || Copy.t("admin.failed_deliveries.error.none", default: "-")
        end
      end
    end
  end
end
