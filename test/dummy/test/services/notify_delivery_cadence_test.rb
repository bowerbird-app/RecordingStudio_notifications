# frozen_string_literal: true

require "test_helper"

class NotifyDeliveryCadenceTest < ActiveSupport::TestCase
  class ImmediateOnlyAdapter
    def deliver(notification:, delivery:); end
  end

  class CapturingAdapter
    attr_accessor :rollup_error
    attr_reader :calls, :rollup_calls

    def initialize
      @calls = []
      @rollup_calls = []
    end

    def deliver(notification:, delivery:)
      @calls << [notification.id, delivery.id]
    end

    def deliver_rollup(notifications:, deliveries:, rollup_key:, cadence:, period_starts_at:, period_ends_at:, idempotency_key:)
      @rollup_calls << {
        notification_ids: notifications.map(&:id),
        delivery_ids: deliveries.map(&:id),
        rollup_key: rollup_key,
        cadence: cadence,
        period_starts_at: period_starts_at,
        period_ends_at: period_ends_at,
        idempotency_key: idempotency_key
      }
      raise rollup_error if rollup_error
    end
  end

  setup do
    @recipient = User.create!(
      email: "delivery-cadence-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @adapter = CapturingAdapter.new
    @original_rollup_delivery_enabled = RecordingStudioNotifications.configuration.rollup_delivery_enabled
    RecordingStudioNotifications.configuration.rollup_delivery_enabled = true
    RecordingStudioNotifications.channels.register(:rollup_test, @adapter)
    register_type(:immediate_delivery_test, allowed_cadences: [:individual], default_cadence: :individual)
    register_type(:grouped_delivery_test, allowed_cadences: %i[individual weekly], default_cadence: :weekly)
    register_type(:grouped_in_app_delivery_test, allowed_cadences: [:daily], default_cadence: :daily, channels: [:in_app])
  end

  teardown do
    RecordingStudioNotifications.configuration.rollup_delivery_enabled = @original_rollup_delivery_enabled
  end

  test "individual cadence delivers each external source notification immediately" do
    notification = RecordingStudioNotifications.notify(
      notification_type: :immediate_delivery_test,
      recipient: @recipient,
      title: "Immediate delivery",
      deliver_later: false
    )
    delivery = notification.deliveries.sole

    assert delivery.delivered?
    refute delivery.deferred_rollup?
    assert_nil delivery.metadata["rollup_key"]
    assert_equal [[notification.id, delivery.id]], @adapter.calls
  end

  test "grouped external cadence creates a pending rollup delivery without dispatching it" do
    travel_to Time.utc(2026, 7, 8, 12) do
      notification = RecordingStudioNotifications.notify(
        notification_type: :grouped_delivery_test,
        recipient: @recipient,
        title: "Weekly delivery",
        deliver_later: false
      )
      delivery = notification.deliveries.sole

      assert delivery.pending?
      assert delivery.deferred_rollup?
      assert_equal true, delivery.metadata["rollup"]
      assert_equal "weekly", delivery.metadata["cadence"]
      assert_equal "2026-07-06T00:00:00Z", delivery.metadata["period_starts_at"]
      assert_equal "2026-07-13T00:00:00Z", delivery.metadata["period_ends_at"]
      assert_includes delivery.metadata["rollup_key"], "/grouped_delivery_test/rollup_test/weekly/"
      assert_empty @adapter.calls
    end
  end

  test "grouped in-app delivery remains immediate while external rollups are deferred" do
    notification = RecordingStudioNotifications.notify(
      notification_type: :grouped_in_app_delivery_test,
      recipient: @recipient,
      title: "Daily inbox notification",
      deliver_later: false
    )
    delivery = notification.deliveries.sole

    assert_equal "in_app", delivery.channel
    assert delivery.delivered?
    refute delivery.deferred_rollup?
  end

  test "one closed rollup period dispatches all associated source deliveries once" do
    travel_to Time.utc(2026, 7, 8, 12) do
      first = notify_grouped("First weekly delivery")
      second = notify_grouped("Second weekly delivery")

      RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2026, 7, 13, 0))

      assert_equal 1, @adapter.rollup_calls.size
      rollup = @adapter.rollup_calls.sole
      assert_equal [first.id, second.id].sort, rollup[:notification_ids].sort
      assert_equal :weekly, rollup[:cadence]
      assert_equal rollup[:rollup_key], rollup[:idempotency_key]
      assert_equal Time.utc(2026, 7, 6), rollup[:period_starts_at]
      assert_equal Time.utc(2026, 7, 13), rollup[:period_ends_at]
      assert first.deliveries.sole.reload.delivered?
      assert second.deliveries.sole.reload.delivered?

      RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2026, 7, 13, 1))
      assert_equal 1, @adapter.rollup_calls.size
    end
  end

  test "failed closed rollups remain retryable with the same idempotency key" do
    travel_to Time.utc(2026, 7, 8, 12) do
      notification = notify_grouped("Retry weekly delivery")
      delivery = notification.deliveries.sole
      @adapter.rollup_error = StandardError.new("provider unavailable")

      RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2026, 7, 13, 0))

      assert delivery.reload.failed?
      assert_equal "provider unavailable", delivery.error_message
      first_key = delivery.metadata.fetch("rollup_key")

      @adapter.rollup_error = nil
      RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2026, 7, 13, 1))

      assert delivery.reload.delivered?
      assert_equal first_key, @adapter.rollup_calls.last.fetch(:idempotency_key)
    end
  end

  test "active rollup reservations prevent duplicate dispatch" do
    travel_to Time.utc(2026, 7, 8, 12) do
      notification = notify_grouped("Reserved weekly delivery")
      delivery = notification.deliveries.sole
      delivery.reserve_rollup!(at: Time.utc(2026, 7, 13, 0, 55))

      RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2026, 7, 13, 1))

      assert delivery.reload.processing?
      assert_empty @adapter.rollup_calls
    end
  end

  test "stale rollup reservations are released and retried" do
    travel_to Time.utc(2026, 7, 8, 12) do
      notification = notify_grouped("Stale reserved weekly delivery")
      delivery = notification.deliveries.sole
      delivery.reserve_rollup!(at: Time.utc(2026, 7, 12, 23))

      RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2026, 7, 13, 0))

      assert delivery.reload.delivered?
      assert_equal 1, @adapter.rollup_calls.size
    end
  end

  test "disabled rollout leaves closed external rollups pending" do
    travel_to Time.utc(2026, 7, 8, 12) do
      notification = notify_grouped("Disabled weekly delivery")
      delivery = notification.deliveries.sole
      RecordingStudioNotifications.configuration.rollup_delivery_enabled = false

      RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2026, 7, 13, 0))

      assert delivery.reload.pending?
      assert_empty @adapter.rollup_calls
    end
  end

  test "grouped external delivery requires a rollup-capable adapter" do
    RecordingStudioNotifications.channels.register(:immediate_only_test, ImmediateOnlyAdapter.new)
    register_type(
      :unsupported_rollup_delivery_test,
      allowed_cadences: [:weekly],
      default_cadence: :weekly,
      channels: [:immediate_only_test]
    )

    error = nil
    assert_no_difference -> { RecordingStudioNotifications::Notification.count } do
      error = assert_raises(ArgumentError) do
        RecordingStudioNotifications.notify(
          notification_type: :unsupported_rollup_delivery_test,
          recipient: @recipient,
          title: "Unsupported grouped delivery",
          deliver_later: false
        )
      end
    end

    assert_includes error.message, "channel does not support grouped delivery: immediate_only_test"
  end

  private

  def register_type(key, allowed_cadences:, default_cadence:, channels: [:rollup_test])
    RecordingStudioNotifications.notification_types.register(
      key,
      label: key.to_s.humanize,
      scope: :global,
      default_channels: channels,
      available_channels: channels,
      allowed_cadences: allowed_cadences,
      default_cadence: default_cadence
    )
  end

  def notify_grouped(title)
    RecordingStudioNotifications.notify(
      notification_type: :grouped_delivery_test,
      recipient: @recipient,
      title: title,
      deliver_later: false
    )
  end
end