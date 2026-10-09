# frozen_string_literal: true

require "test_helper"

class MetricsTest < Minitest::Test
  def test_metrics_register_with_operations_expose_and_staff_view
    metrics = File.read(File.expand_path("../lib/recording_studio_notifications/metrics.rb", __dir__))
    engine = File.read(File.expand_path("../lib/recording_studio_notifications/engine.rb", __dir__))
    gemspec = File.read(File.expand_path("../recording_studio_notifications.gemspec", __dir__))
    dummy_metrics = File.read(File.expand_path("dummy/config/initializers/recording_studio_metrics.rb", __dir__))

    assert_includes metrics, "RecordingStudioMetrics.register"
    assert_includes metrics, ":notifications"
    assert_includes metrics, "RecordingStudioNotifications::Notification"
    assert_includes metrics, "timeseries :sent_over_time"
    assert_includes metrics, "field: :created_at"
    assert_includes metrics, "breakdown :by_type"
    assert_includes metrics, "field: :notification_type"
    assert_includes metrics, "custom :read_vs_unread"
    assert_includes metrics, "relation.read.distinct.count"
    assert_includes metrics, "relation.unread.distinct.count"
    assert_includes metrics, ":notification_deliveries"
    assert_includes metrics, "RecordingStudioNotifications::Delivery"
    assert_includes metrics, "breakdown :by_status"
    assert_includes metrics, "field: :status"
    assert_includes metrics, "breakdown :by_channel"
    assert_includes metrics, "field: :channel"
    assert_includes metrics, "blast_radius: :site"
    assert_includes metrics, "expose: EXPOSE"
    assert_includes metrics, "api: [API]"
    assert_includes metrics, "API = :operations"
    assert_includes metrics, "Api::Access.can_view?"
    refute_includes metrics, "RecordingStudioMetrics::Api.register!"
    refute_includes metrics, "respond_to?"
    refute_includes metrics, "rescue"

    assert_includes engine, "RecordingStudioNotifications::Metrics.register!"
    refute_includes engine, "RecordingStudioMetrics::Api.register!"

    assert_includes gemspec, 'spec.add_dependency "recording_studio_metrics", "~> 0.2"'
    assert_includes dummy_metrics, "RecordingStudioMetrics::Api.register!(api: :operations)"
  end
end
