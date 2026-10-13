# frozen_string_literal: true

require "test_helper"

class ValidationErrorTypesTest < ActiveSupport::TestCase
  setup do
    @user = User.find_or_create_by!(email: "validation-errors@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
  end

  test "notification string error types match main english details" do
    notification = RecordingStudioNotifications::Notification.new(
      notification_type: "not_a_real_type",
      title: "Title",
      recipient: @user,
      url: "javascript:alert(1)"
    )

    refute notification.valid?

    assert_equal [{ error: "is not registered" }], notification.errors.details[:notification_type]
    assert_equal [{ error: "is not safe" }], notification.errors.details[:url]
    assert_includes notification.errors[:notification_type], "is not registered"
    assert_includes notification.errors[:url], "is not safe"
  end

  test "preference string error types match main english details" do
    preference = RecordingStudioNotifications::Preference.new(
      recipient: @user,
      notification_type: "not_a_real_type",
      channel: "in_app",
      enabled: true
    )

    refute preference.valid?

    assert_equal [{ error: "is not registered" }], preference.errors.details[:notification_type]
    assert_includes preference.errors[:notification_type], "is not registered"

    shape = RecordingStudioNotifications::Preference.new(
      recipient: @user,
      notification_type: "generic",
      channel: nil,
      enabled: true,
      cadence: nil
    )
    refute shape.valid?
    assert_equal(
      [{ error: "must be either a channel preference or a cadence override" }],
      shape.errors.details[:base]
    )
  end

  test "delivery string error types match main english details" do
    delivery = RecordingStudioNotifications::Delivery.new(
      channel: "not_a_real_channel",
      status: "pending"
    )

    refute delivery.valid?
    assert_equal [{ error: "is not registered" }], delivery.errors.details[:channel]
  end

  test "mark_failed! persists main english for channel validation under fr" do
    notification = RecordingStudioNotifications::Notification.create!(
      notification_type: "generic",
      title: "Title",
      recipient: @user
    )
    delivery = notification.deliveries.create!(channel: "in_app", status: "pending")

    previous_locales = I18n.available_locales
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr]
    I18n.backend.store_translations(
      :fr,
      {
        recording_studio: {
          notifications: {
            errors: {
              delivery: {
                channel_not_registered: "n’est pas enregistré"
              }
            }
          }
        }
      }
    )

    I18n.with_locale(:fr) do
      invalid = RecordingStudioNotifications::Delivery.new(
        notification: notification,
        channel: "not_a_real_channel",
        status: "pending"
      )
      refute invalid.valid?
      assert_equal [{ error: "is not registered" }], invalid.errors.details[:channel]
      assert_equal ["is not registered"], invalid.errors[:channel]

      delivery.mark_failed!(StandardError.new(invalid.errors[:channel].first))
    end

    assert_equal "is not registered", delivery.reload.error_message
  ensure
    I18n.available_locales = previous_locales if previous_locales
  end

  test "mark_failed! persists main english when host overrides delivery channel key" do
    notification = RecordingStudioNotifications::Notification.create!(
      notification_type: "generic",
      title: "Title",
      recipient: @user
    )
    delivery = notification.deliveries.create!(channel: "in_app", status: "pending")

    I18n.backend.store_translations(
      :en,
      {
        recording_studio: {
          notifications: {
            errors: {
              delivery: {
                channel_not_registered: "HOST is not registered"
              }
            }
          }
        }
      }
    )

    I18n.with_locale(:en) do
      invalid = RecordingStudioNotifications::Delivery.new(
        notification: notification,
        channel: "not_a_real_channel",
        status: "pending"
      )
      refute invalid.valid?
      assert_equal [{ error: "is not registered" }], invalid.errors.details[:channel]
      assert_equal ["is not registered"], invalid.errors[:channel]

      delivery.mark_failed!(StandardError.new(invalid.errors[:channel].first))
    end

    assert_equal "is not registered", delivery.reload.error_message
  ensure
    I18n.backend.store_translations(
      :en,
      {
        recording_studio: {
          notifications: {
            errors: {
              delivery: {
                channel_not_registered: "is not registered"
              }
            }
          }
        }
      }
    )
  end

  test "french full messages use translated string types" do
    previous_locales = I18n.available_locales
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr]

    shape = RecordingStudioNotifications::Preference.new(
      recipient: @user,
      notification_type: "generic",
      channel: nil,
      enabled: true,
      cadence: nil
    )

    I18n.with_locale(:fr) do
      refute shape.valid?
      assert_equal(
        [{ error: "doit être une préférence de canal ou une fréquence" }],
        shape.errors.details[:base]
      )
      assert_includes shape.errors.full_messages.join(" "), "doit être une préférence de canal ou une fréquence"
    end
  ensure
    I18n.available_locales = previous_locales if previous_locales
  end

  test "host override wins for validation string type" do
    I18n.backend.store_translations(
      :en,
      {
        recording_studio: {
          notifications: {
            errors: {
              preference: {
                invalid_shape: "HOST must be either a channel preference or a cadence override"
              }
            }
          }
        }
      }
    )

    shape = RecordingStudioNotifications::Preference.new(
      recipient: @user,
      notification_type: "generic",
      channel: nil,
      enabled: true,
      cadence: nil
    )

    refute shape.valid?
    assert_equal(
      [{ error: "HOST must be either a channel preference or a cadence override" }],
      shape.errors.details[:base]
    )
  ensure
    I18n.backend.store_translations(
      :en,
      {
        recording_studio: {
          notifications: {
            errors: {
              preference: {
                invalid_shape: "must be either a channel preference or a cadence override"
              }
            }
          }
        }
      }
    )
  end
end

