# frozen_string_literal: true

require "test_helper"

class DeliveryErrorMessagePersistenceTest < ActiveSupport::TestCase
  MAIN_PREFERENCE_SHAPE_MESSAGE =
    "Validation failed: must be either a channel preference or a cadence override"
  HOST_PREFERENCE_SHAPE_KEY =
    "recording_studio.notifications.errors.preference.invalid_shape"
  HOST_PREFERENCE_SHAPE_MESSAGE =
    "HOST must be either a channel preference or a cadence override"
  FRENCH_PREFERENCE_SHAPE_MESSAGE =
    "doit être une préférence de canal ou une fréquence"

  class InvalidPreferenceAdapter
    def deliver(notification:, delivery:)
      save_invalid_preference!(notification.recipient)
    end

    def deliver_rollup(notifications:, deliveries:, rollup_key:, cadence:, period_starts_at:, period_ends_at:, idempotency_key:)
      save_invalid_preference!(notifications.first.recipient)
    end

    private

    def save_invalid_preference!(recipient)
      RecordingStudioNotifications::Preference.create!(
        recipient: recipient,
        notification_type: "generic",
        channel: nil,
        enabled: true,
        cadence: nil
      )
    end
  end

  setup do
    @recipient = User.create!(
      email: "delivery-error-message-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @adapter = InvalidPreferenceAdapter.new
    @original_rollup_delivery_enabled = RecordingStudioNotifications.configuration.rollup_delivery_enabled
    RecordingStudioNotifications.configuration.rollup_delivery_enabled = true
    RecordingStudioNotifications.channels.register(:error_message_persistence_test, @adapter)
    RecordingStudioNotifications.notification_types.register(
      :error_message_persistence_immediate,
      label: "Error message persistence immediate",
      scope: :global,
      default_channels: [:error_message_persistence_test],
      available_channels: [:error_message_persistence_test],
      allowed_cadences: [:individual],
      default_cadence: :individual
    )
    RecordingStudioNotifications.notification_types.register(
      :error_message_persistence_grouped,
      label: "Error message persistence grouped",
      scope: :global,
      default_channels: [:error_message_persistence_test],
      available_channels: [:error_message_persistence_test],
      allowed_cadences: %i[individual weekly],
      default_cadence: :weekly
    )
  end

  teardown do
    RecordingStudioNotifications.configuration.rollup_delivery_enabled = @original_rollup_delivery_enabled
  end

  test "DeliveryJob persists main english when invalid preference save runs under fr" do
    previous_locales = I18n.available_locales
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr]
    I18n.t("recording_studio.notifications.inbox.title")
    I18n.backend.store_translations(
      :fr,
      {
        recording_studio: {
          notifications: {
            errors: {
              preference: {
                invalid_shape: FRENCH_PREFERENCE_SHAPE_MESSAGE
              }
            }
          }
        }
      }
    )
    assert_equal FRENCH_PREFERENCE_SHAPE_MESSAGE, I18n.t(HOST_PREFERENCE_SHAPE_KEY, locale: :fr)

    notification = nil
    I18n.with_locale(:fr) do
      notification = RecordingStudioNotifications::Notification.create!(
        notification_type: "error_message_persistence_immediate",
        title: "Immediate failure",
        recipient: @recipient
      )
      notification.deliveries.create!(
        channel: "error_message_persistence_test",
        status: "pending"
      )
      RecordingStudioNotifications::DeliveryJob.perform_now(notification.id)
    end

    delivery = notification.deliveries.sole
    assert delivery.reload.failed?
    assert_equal MAIN_PREFERENCE_SHAPE_MESSAGE, delivery.error_message
  ensure
    I18n.available_locales = previous_locales if previous_locales
  end

  test "DeliveryJob persists main english when host overrides preference validation key" do
    I18n.t("recording_studio.notifications.inbox.title")
    I18n.backend.store_translations(
      :en,
      {
        recording_studio: {
          notifications: {
            errors: {
              preference: {
                invalid_shape: HOST_PREFERENCE_SHAPE_MESSAGE
              }
            }
          }
        }
      }
    )
    assert_equal HOST_PREFERENCE_SHAPE_MESSAGE, I18n.t(HOST_PREFERENCE_SHAPE_KEY)

    notification = RecordingStudioNotifications::Notification.create!(
      notification_type: "error_message_persistence_immediate",
      title: "Immediate host override failure",
      recipient: @recipient
    )
    notification.deliveries.create!(
      channel: "error_message_persistence_test",
      status: "pending"
    )
    RecordingStudioNotifications::DeliveryJob.perform_now(notification.id)

    delivery = notification.deliveries.sole
    assert delivery.reload.failed?
    assert_equal MAIN_PREFERENCE_SHAPE_MESSAGE, delivery.error_message
  end

  test "RollupDeliveryJob persists main english when invalid preference save runs under fr" do
    previous_locales = I18n.available_locales
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr]
    I18n.t("recording_studio.notifications.inbox.title")
    I18n.backend.store_translations(
      :fr,
      {
        recording_studio: {
          notifications: {
            errors: {
              preference: {
                invalid_shape: FRENCH_PREFERENCE_SHAPE_MESSAGE
              }
            }
          }
        }
      }
    )
    assert_equal FRENCH_PREFERENCE_SHAPE_MESSAGE, I18n.t(HOST_PREFERENCE_SHAPE_KEY, locale: :fr)

    delivery = nil
    travel_to Time.utc(2026, 7, 8, 12) do
      I18n.with_locale(:fr) do
        notification = RecordingStudioNotifications.notify(
          notification_type: :error_message_persistence_grouped,
          recipient: @recipient,
          title: "Grouped failure",
          deliver_later: false
        )
        delivery = notification.deliveries.sole
        assert delivery.pending?
        assert delivery.deferred_rollup?

        RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2026, 7, 13, 0))
      end
    end

    assert delivery.reload.failed?
    assert_equal MAIN_PREFERENCE_SHAPE_MESSAGE, delivery.error_message
  ensure
    I18n.available_locales = previous_locales if previous_locales
  end

  test "RollupDeliveryJob persists main english when host overrides preference validation key" do
    I18n.t("recording_studio.notifications.inbox.title")
    I18n.backend.store_translations(
      :en,
      {
        recording_studio: {
          notifications: {
            errors: {
              preference: {
                invalid_shape: HOST_PREFERENCE_SHAPE_MESSAGE
              }
            }
          }
        }
      }
    )
    assert_equal HOST_PREFERENCE_SHAPE_MESSAGE, I18n.t(HOST_PREFERENCE_SHAPE_KEY)

    delivery = nil
    travel_to Time.utc(2026, 7, 8, 12) do
      notification = RecordingStudioNotifications.notify(
        notification_type: :error_message_persistence_grouped,
        recipient: @recipient,
        title: "Grouped host override failure",
        deliver_later: false
      )
      delivery = notification.deliveries.sole
      assert delivery.pending?
      assert delivery.deferred_rollup?

      RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2026, 7, 13, 0))
    end

    assert delivery.reload.failed?
    assert_equal MAIN_PREFERENCE_SHAPE_MESSAGE, delivery.error_message
  end
end
