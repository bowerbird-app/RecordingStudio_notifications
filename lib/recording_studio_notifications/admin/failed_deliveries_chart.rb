# frozen_string_literal: true

return unless defined?(RecordingStudioAdmin)

module RecordingStudioNotifications
  module Admin
    module FailedDeliveriesChart
      METRIC = "notification_deliveries.failed_by_channel_over_time"
      SCREEN_KEY = "recording_studio_notifications_failed_deliveries"
      WIDGET_KEY = "widgets.recording_studio_notifications.failed_deliveries"
      INTERVAL = :day
      INTERVALS = %i[hour day week month year].freeze

      module_function

      def series(admin_context)
        result = execute(admin_context)
        lines = Array(result.try(:groups)).filter_map { |group| series_for_group(group) }
        leftover = leftover_series(result)
        lines << leftover if leftover
        return lines if lines.any?

        [{ name: Copy.t("admin.failed_deliveries.title", default: "Failed deliveries"), data: points(result.data) }]
      end

      def screen_series(admin_context)
        series_from_relation(
          relation_from(admin_context),
          interval: interval_from(admin_context),
          range: admin_context.try(:filter_value, :date_range)
        )
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

      def interval_from(admin_context)
        value = admin_context.try(:filter_value, :group_by) if admin_context.respond_to?(:filter_value)
        key = value.to_s.downcase.to_sym
        INTERVALS.include?(key) ? key : INTERVAL
      end

      def relation_from(admin_context)
        result = admin_context.try(:query_result)
        return result.relation if result.respond_to?(:relation)

        FailedDeliveriesScreen.query.call(admin_context)
      end

      def series_from_relation(relation, interval:, range: nil)
        interval = INTERVALS.include?(interval.to_s.to_sym) ? interval.to_s.to_sym : INTERVAL
        counts = counts_by_channel_and_bucket(relation, interval)
        starts = bucket_starts(counts, range, interval)
        channels = counts.keys.map(&:first).uniq
        return [{ name: Copy.t("admin.failed_deliveries.title", default: "Failed deliveries"), data: [] }] if channels.empty?

        channels.map do |channel|
          {
            name: channel_name(channel),
            data: starts.map { |start| { x: start, y: counts[[channel, start]].to_i } }
          }
        end
      end

      def counts_by_channel_and_bucket(relation, interval)
        table = RecordingStudioNotifications::Delivery.table_name
        connection = RecordingStudioNotifications::Delivery.connection
        quoted_table = connection.quote_table_name(table)
        quoted_channel = connection.quote_column_name("channel")
        quoted_updated = connection.quote_column_name("updated_at")
        trunc = "DATE_TRUNC(#{connection.quote(interval.to_s)}, #{quoted_table}.#{quoted_updated} AT TIME ZONE 'UTC')"
        grouped = chart_relation(relation).group(Arel.sql("#{quoted_table}.#{quoted_channel}"), Arel.sql(trunc)).count
        grouped.each_with_object({}) do |((channel, value), count), memo|
          start = bucket_start(value, interval)
          next unless start

          memo[[channel, start]] = memo[[channel, start]].to_i + count.to_i
        end
      end

      def chart_relation(relation)
        return relation unless relation.respond_to?(:except)

        relation.except(:includes, :eager_load, :preload, :order, :select)
      end

      def bucket_starts(counts, range, interval)
        counted = counts.keys.map(&:last).compact
        first = bucket_start(range.try(:start_date), interval) || counted.min
        last = bucket_start(range.try(:end_date), interval) || counted.max
        return [] unless first && last

        starts = []
        cursor = first
        while cursor <= last
          starts << cursor
          cursor = advance_bucket(cursor, interval)
        end
        starts
      end

      def bucket_start(value, interval)
        time = coerce_utc_time(value)
        return unless time

        case interval
        when :hour then time.beginning_of_hour
        when :week then time.beginning_of_week
        when :month then time.beginning_of_month
        when :year then time.beginning_of_year
        else time.beginning_of_day
        end
      end

      def advance_bucket(time, interval)
        case interval
        when :hour then time + 1.hour
        when :week then time + 1.week
        when :month then time.next_month.beginning_of_month
        when :year then time.next_year.beginning_of_year
        else time + 1.day
        end
      end

      def coerce_utc_time(value)
        return if value.blank?
        return value.utc.change(usec: 0) if value.respond_to?(:utc)
        return Time.utc(value.year, value.month, value.day) if value.is_a?(Date)

        Time.parse(value.to_s).utc
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
