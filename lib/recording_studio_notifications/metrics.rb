# frozen_string_literal: true

require_relative "api/access"
require "recording_studio_metrics"

module RecordingStudioNotifications
  module Metrics
    NOTIFICATIONS = :notifications
    DELIVERIES = :notification_deliveries
    API = :operations
    EXPOSE = { api: [API] }.freeze
    AUTHORIZE = ->(context) { RecordingStudioNotifications::Api::Access.can_view?(context) }

    module_function

    def register!
      register_notifications!
      register_deliveries!
    end

    def register_notifications!
      RecordingStudioMetrics.register(
        NOTIFICATIONS,
        model: RecordingStudioNotifications::Notification,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioNotifications::Metrics.define_notifications(self) }
    end

    def register_deliveries!
      RecordingStudioMetrics.register(
        DELIVERIES,
        model: RecordingStudioNotifications::Delivery,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) { RecordingStudioNotifications::Metrics.define_deliveries(self) }
    end

    def define_notifications(dsl)
      dsl.timeseries :sent_over_time, title: "Notifications sent", field: :created_at, expose: EXPOSE
      dsl.breakdown :by_type, title: "Notifications by type", field: :notification_type, expose: EXPOSE
      dsl.custom :read_vs_unread,
                 result_type: :breakdown,
                 title: "Read vs unread",
                 expose: EXPOSE,
                 &read_vs_unread_calculator
    end

    def define_deliveries(dsl)
      dsl.breakdown :by_status, title: "Deliveries by status", field: :status, expose: EXPOSE
      dsl.breakdown :by_channel, title: "Deliveries by channel", field: :channel, expose: EXPOSE
    end

    def read_vs_unread_calculator
      lambda do |relation, _context|
        [
          { key: "read", value: relation.read.distinct.count },
          { key: "unread", value: relation.unread.distinct.count }
        ]
      end
    end
  end
end
