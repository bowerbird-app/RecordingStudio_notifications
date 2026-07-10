# frozen_string_literal: true

require "date"

module RecordingStudioNotifications
  module Services
    class DigestCollector
      Period = Struct.new(:starts_at, :ends_at, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def self.period_for(cadence:, at: Time.current)
        new(cadence: cadence, at: at).period
      end

      def initialize(notification: nil, cadence:, at: Time.current)
        @notification = notification
        @cadence = cadence.to_sym
        @at = at
      end

      def call
        raise ArgumentError, "notification is required" unless @notification
        raise ArgumentError, "cadence must be consolidated" unless consolidated_cadence?

        NotificationDigest.transaction do
          digest = find_or_create_digest!
          attach_notification!(digest)
        end
      end

      def period
        case @cadence
        when :daily
          period_from(day_start, midnight_for(@at.to_date + 1))
        when :every_other_day
          starts_at = midnight_for(alternate_day_start)
          period_from(starts_at, midnight_for(alternate_day_start + 2))
        when :weekly
          week_start = monday_for(@at.to_date)
          starts_at = midnight_for(week_start)
          period_from(starts_at, midnight_for(week_start + 7))
        when :biweekly
          starts_at = midnight_for(biweekly_start)
          period_from(starts_at, midnight_for(biweekly_start + 14))
        when :monthly
          month_start = Date.new(@at.year, @at.month, 1)
          period_from(midnight_for(month_start), midnight_for(month_start >> 1))
        else
          raise ArgumentError, "cadence must be consolidated"
        end
      end

      private

      def consolidated_cadence?
        NotificationTypeRegistry::CADENCES.include?(@cadence) && @cadence != :every_notification
      end

      def find_or_create_digest!
        digest_period = period
        attributes = {
          recipient: @notification.recipient,
          notification_type: @notification.notification_type,
          root_recording: @notification.root_recording,
          cadence: @cadence.to_s,
          status: "pending",
          period_starts_at: digest_period.starts_at
        }

        NotificationDigest.pending.find_by(attributes) || NotificationDigest.create!(
          **attributes,
          period_ends_at: digest_period.ends_at
        )
      rescue ActiveRecord::RecordNotUnique
        NotificationDigest.pending.find_by!(attributes)
      end

      def attach_notification!(digest)
        existing_item = NotificationDigestItem.find_by(notification: @notification)
        return existing_item.digest if existing_item

        digest.items.create!(notification: @notification)
        digest
      rescue ActiveRecord::RecordNotUnique
        NotificationDigestItem.find_by!(notification: @notification).digest
      end

      def day_start
        midnight_for(@at.to_date)
      end

      def alternate_day_start
        anchor = Date.new(2000, 1, 1)
        @at.to_date - ((@at.to_date - anchor) % 2)
      end

      def biweekly_start
        anchor = Date.new(2000, 1, 3)
        weeks_since_anchor = ((@at.to_date - anchor) / 7).floor
        anchor + ((weeks_since_anchor / 2) * 14)
      end

      def midnight_for(date)
        return Time.zone.local(date.year, date.month, date.day) if Time.respond_to?(:zone) && Time.zone

        Time.new(date.year, date.month, date.day, 0, 0, 0, @at.utc_offset)
      end

      def monday_for(date)
        date - ((date.wday + 6) % 7)
      end

      def period_from(starts_at, ends_at)
        Period.new(starts_at: starts_at, ends_at: ends_at)
      end
    end
  end
end