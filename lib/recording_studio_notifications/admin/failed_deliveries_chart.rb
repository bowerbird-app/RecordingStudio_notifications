# frozen_string_literal: true

return unless defined?(RecordingStudioAdmin)

module RecordingStudioNotifications
  module Admin
    module FailedDeliveriesChart
      METRIC = "notification_deliveries.failed_by_channel_over_time"
      SCREEN_KEY = "recording_studio_notifications_failed_deliveries"
      WIDGET_KEY = "widgets.recording_studio_notifications.failed_deliveries"
      INTERVAL = :day

      module_function

      def series(admin_context)
        result = execute(admin_context)
        lines = Array(result.try(:groups)).filter_map { |group| series_for_group(group) }
        leftover = leftover_series(result)
        lines << leftover if leftover
        return lines if lines.any?

        [{ name: Copy.t("admin.failed_deliveries.title", default: "Failed deliveries"), data: points(result.data) }]
      end

      def total(admin_context)
        Array(execute(admin_context).data).sum { |row| (row[:value] || row["value"]).to_i }
      end

      def execute(admin_context)
        RecordingStudioMetrics.execute(
          METRIC,
          context: metric_context(admin_context),
          interval: INTERVAL,
          group_by: :channel
        )
      end

      def metric_context(admin_context)
        RecordingStudioMetrics::Admin.context_from_admin(
          admin_context,
          scope: :site,
          site_authorized: true
        )
      end

      def series_for_group(group)
        key = group[:key] || group["key"]
        return if key.nil?

        { name: channel_name(key), data: points(group[:data] || group["data"]) }
      end

      def leftover_series(result)
        other = result.try(:other)
        return unless other

        { name: Copy.t("admin.failed_deliveries.other", default: "Other"), data: points(other[:data] || other["data"]) }
      end

      # ApexCharts 3.45.1 (no xaxis type datetime) treats a tuple's string date as
      # a number, so every point lands at x=0 and the line collapses. `{ x:, y: }`
      # hashes are what Admin charts that render (for example api_requests) emit.
      def points(rows)
        Array(rows).map do |row|
          {
            x: row[:date] || row["date"],
            y: (row[:value] || row["value"]).to_i
          }
        end
      end

      def channel_name(key)
        Copy.t("channels.#{key}", default: key.to_s.tr("_", " "))
      end
    end
  end
end
