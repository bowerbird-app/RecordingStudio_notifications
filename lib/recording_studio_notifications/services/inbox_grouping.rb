# frozen_string_literal: true

require "active_support/time"
require_relative "cadence_period"

module RecordingStudioNotifications
  module Services
    class InboxGrouping
      Section = Struct.new(:notification_type, :label, :groups, keyword_init: true)

      Group = Struct.new(
        :notification_type,
        :notification_type_label,
        :cadence,
        :period_starts_at,
        :period_ends_at,
        :time_zone,
        :notifications,
        :id,
        keyword_init: true
      ) do
        def individual?
          cadence == :individual
        end

        def unread_count
          notifications.count(&:unread?)
        end

        def latest_notification
          notifications.first
        end

        def period_label
          start_date = period_starts_at.to_date
          end_date = (period_ends_at - 1.second).to_date

          case cadence
          when :daily
            start_date.strftime("%b %-d")
          when :monthly
            start_date.strftime("%b %Y")
          else
            "#{start_date.strftime('%b %-d')} – #{end_date.strftime('%b %-d')}"
          end
        end

        def heading
          unread_text = unread_count.positive? ? "#{unread_count} unread" : "All read"
          "#{period_label} · #{unread_text} · #{notifications.size} notifications"
        end
      end

      def initialize(recipient:, notifications:, time_zone: nil, cadence_resolver: nil)
        @recipient = recipient
        @notifications = Array(notifications)
        @time_zone = resolve_time_zone(time_zone)
        @cadence_resolver = cadence_resolver || method(:effective_cadence_for)
      end

      def call
        grouped_notifications = @notifications.each_with_object({}) do |notification, groups|
          type = notification_type_for(notification)
          cadence = @cadence_resolver.call(notification, type)
          period_starts_at, period_ends_at = period_for(notification.created_at, cadence)
          key = grouping_key(notification, cadence, period_starts_at)

          groups[key] ||= Group.new(
            notification_type: type.key,
            notification_type_label: type.label,
            cadence: cadence,
            period_starts_at: period_starts_at,
            period_ends_at: period_ends_at,
            time_zone: @time_zone,
            notifications: [],
            id: group_id(type.key, cadence, period_starts_at, notification)
          )
          groups[key].notifications << notification
        end

        grouped_notifications.each_value do |group|
          group.notifications.sort_by! { |notification| [notification.created_at, notification.id.to_s] }.reverse!
        end

        grouped_notifications.values
                             .group_by(&:notification_type)
                             .map do |type, groups|
          sorted_groups = groups.sort_by { |group| [group.latest_notification.created_at, group.id] }.reverse
          Section.new(notification_type: type, label: sorted_groups.first.notification_type_label,
                      groups: sorted_groups)
        end
          .sort_by { |section| [section.groups.first.latest_notification.created_at, section.notification_type.to_s] }
                             .reverse
      end

      private

      def effective_cadence_for(notification, type)
        return :individual unless type.respond_to?(:default_cadence)
        return :individual unless RecordingStudioNotifications.configuration.rollup_delivery_enabled

        Preference.cadence_for(
          recipient: @recipient,
          notification_type: notification.notification_type,
          default: type.default_cadence
        )
      end

      def notification_type_for(notification)
        RecordingStudioNotifications.notification_types.fetch(notification.notification_type)
      end

      def grouping_key(notification, cadence, period_starts_at)
        return [notification.notification_type, cadence, notification.id] if cadence == :individual

        [notification.notification_type, cadence, period_starts_at]
      end

      def group_id(type, cadence, period_starts_at, notification)
        suffix = cadence == :individual ? notification.id : period_starts_at.to_i
        "notification-group-#{type}-#{cadence}-#{suffix}"
      end

      def period_for(created_at, cadence)
        period = CadencePeriod.for(timestamp: created_at, cadence: cadence, time_zone: @time_zone)
        [period.starts_at, period.ends_at]
      end

      def resolve_time_zone(time_zone)
        candidate = time_zone.presence || @recipient.try(:time_zone).presence || Time.zone
        ActiveSupport::TimeZone[candidate] || Time.zone || ActiveSupport::TimeZone["UTC"]
      end
    end
  end
end
