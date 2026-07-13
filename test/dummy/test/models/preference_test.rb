# frozen_string_literal: true

require "test_helper"

class RecordingStudioNotificationsPreferenceTest < ActiveSupport::TestCase
  setup do
    @recipient = User.create!(
      email: "cadence-preference-#{SecureRandom.uuid}@example.test",
      password: "password123",
      password_confirmation: "password123"
    )
    RecordingStudioNotifications.notification_types.register(
      :cadence_preference_test,
      label: "Cadence preference test",
      default_channels: [:in_app],
      available_channels: [:in_app],
      allowed_cadences: %i[individual daily weekly],
      default_cadence: :weekly
    )
  end

  test "channel and cadence preferences are stored separately" do
    channel_preference = RecordingStudioNotifications::Preference.set!(
      recipient: @recipient,
      notification_type: :cadence_preference_test,
      channel: :in_app,
      enabled: false
    )
    cadence_preference = RecordingStudioNotifications::Preference.set_cadence!(
      recipient: @recipient,
      notification_type: :cadence_preference_test,
      cadence: :daily
    )

    assert_equal "in_app", channel_preference.channel
    assert_equal false, channel_preference.enabled
    assert_nil channel_preference.cadence
    assert_nil cadence_preference.channel
    assert_nil cadence_preference.enabled
    assert_equal "daily", cadence_preference.cadence
  end

  test "cadence preference falls back without creating a row and removes default overrides" do
    assert_equal :weekly, RecordingStudioNotifications::Preference.cadence_for(
      recipient: @recipient,
      notification_type: :cadence_preference_test,
      default: :weekly
    )
    assert_equal 0, RecordingStudioNotifications::Preference.where(recipient: @recipient, channel: nil).count

    RecordingStudioNotifications::Preference.set_cadence!(
      recipient: @recipient,
      notification_type: :cadence_preference_test,
      cadence: :daily
    )
    assert_equal :daily, RecordingStudioNotifications::Preference.cadence_for(
      recipient: @recipient,
      notification_type: :cadence_preference_test,
      default: :weekly
    )

    RecordingStudioNotifications::Preference.set_cadence!(
      recipient: @recipient,
      notification_type: :cadence_preference_test,
      cadence: :weekly
    )
    assert_equal 0, RecordingStudioNotifications::Preference.where(recipient: @recipient, channel: nil).count
  end

  test "cadence rows enforce their shape and allowed values" do
    invalid_shape = RecordingStudioNotifications::Preference.new(
      recipient: @recipient,
      notification_type: :cadence_preference_test,
      channel: :in_app,
      enabled: true,
      cadence: :daily
    )

    refute invalid_shape.valid?
    assert_includes invalid_shape.errors[:base], "must be either a channel preference or a cadence override"

    assert_raises(ArgumentError) do
      RecordingStudioNotifications::Preference.set_cadence!(
        recipient: @recipient,
        notification_type: :cadence_preference_test,
        cadence: :monthly
      )
    end
  end

  test "required cadence takes precedence over a saved override" do
    RecordingStudioNotifications.notification_types.register(
      :required_cadence_preference_test,
      label: "Required cadence preference test",
      default_channels: [:in_app],
      available_channels: [:in_app],
      allowed_cadences: %i[daily weekly],
      default_cadence: :weekly,
      required_cadence: :daily
    )
    RecordingStudioNotifications::Preference.create!(
      recipient: @recipient,
      notification_type: :required_cadence_preference_test,
      cadence: :weekly
    )

    assert_equal :daily, RecordingStudioNotifications::Preference.cadence_for(
      recipient: @recipient,
      notification_type: :required_cadence_preference_test,
      default: :weekly
    )
  end
end