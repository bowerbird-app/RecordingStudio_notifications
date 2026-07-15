# frozen_string_literal: true

require "active_support/time"

module RecordingStudioNotifications
  module Services
    class CadencePeriod
      Period = Struct.new(:starts_at, :ends_at, keyword_init: true)

      class << self
        def for(timestamp:, cadence:, time_zone:)
          zone = resolve_time_zone(time_zone)
          local_time = timestamp.in_time_zone(zone)
          start_date = period_start_date(local_time.to_date, cadence)

          Period.new(
            starts_at: local_midnight(zone, start_date),
            ends_at: local_midnight(zone, period_end_date(start_date, cadence))
          )
        end

        private

        def period_start_date(date, cadence)
          case cadence.to_sym
          when :daily, :individual
            date
          when :every_other_day
            stable_period_start(date, Date.new(1970, 1, 1), 2)
          when :weekly
            date.beginning_of_week(:monday)
          when :biweekly
            stable_period_start(date, Date.new(1970, 1, 5), 14)
          when :monthly
            date.beginning_of_month
          else
            raise ArgumentError, "unsupported cadence #{cadence.inspect}"
          end
        end

        def period_end_date(start_date, cadence)
          case cadence.to_sym
          when :daily, :individual then start_date + 1.day
          when :every_other_day then start_date + 2.days
          when :weekly then start_date + 7.days
          when :biweekly then start_date + 14.days
          when :monthly then start_date.next_month
          end
        end

        def stable_period_start(date, anchor, length)
          anchor + (((date - anchor).to_i / length) * length)
        end

        def local_midnight(zone, date)
          zone.local(date.year, date.month, date.day)
        end

        def resolve_time_zone(time_zone)
          return time_zone if time_zone.respond_to?(:local) && time_zone.respond_to?(:name)

          ActiveSupport::TimeZone[time_zone] || Time.zone || ActiveSupport::TimeZone["UTC"]
        end
      end
    end
  end
end
