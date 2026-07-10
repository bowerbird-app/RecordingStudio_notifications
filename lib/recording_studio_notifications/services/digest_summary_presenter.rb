# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    class DigestSummaryPresenter
      def self.call(...)
        new(...).call
      end

      def initialize(digest:)
        @digest = digest
      end

      def call
        {
          title: "#{cadence_label} summary: #{type_label} (#{event_count})",
          body: "#{event_count} #{type_label.downcase} #{event_count == 1 ? 'event' : 'events'} from #{period_label}.",
          icon: type_definition&.icon || :bell,
          destination: nil
        }
      end

      private

      def type_definition
        @type_definition ||= RecordingStudioNotifications.notification_types[@digest.notification_type]
      end

      def type_label
        type_definition&.label || @digest.notification_type.to_s.humanize
      end

      def event_count
        @digest.items.count
      end

      def cadence_label
        @digest.cadence.to_s.humanize
      end

      def period_label
        "#{@digest.period_starts_at.to_date} to #{(@digest.period_ends_at.to_date - 1)}"
      end
    end
  end
end