# frozen_string_literal: true

return unless defined?(RecordingStudioAdmin)

module RecordingStudioNotifications
  module Admin
    module FailedDeliveriesScreenChart
      INTERVALS = FailedDeliveriesChart::INTERVALS
      INTERVAL = FailedDeliveriesChart::INTERVAL

      module_function

      def series(admin_context)
        series_from_relation(
          relation_from(admin_context),
          interval: interval_from(admin_context),
          range: admin_context.try(:filter_value, :date_range)
        )
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
        empty_name = Copy.t("admin.failed_deliveries.title", default: "Failed deliveries")
        return [{ name: empty_name, data: [] }] if channels.empty?

        channels.map do |channel|
          {
            name: FailedDeliveriesChart.channel_name(channel),
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
