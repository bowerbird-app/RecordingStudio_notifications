# frozen_string_literal: true

require "test_helper"

class NotifyEmptyChannelsTest < ActiveSupport::TestCase
  setup do
    @recipient = User.create!(
      email: "empty-channels-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :empty_channel_notify_test,
      label: "Empty channel notify test",
      scope: :global,
      default_channels: [],
      required_channels: [],
      available_channels: [:in_app]
    )
  end

  test "notify with no selected channels delivers nothing" do
    assert_no_difference -> { RecordingStudioNotifications::Notification.where(recipient: @recipient).count } do
      result = RecordingStudioNotifications.notify(
        notification_type: :empty_channel_notify_test,
        recipient: @recipient,
        title: "Quiet kind",
        idempotency_key: "empty-channel-#{SecureRandom.uuid}"
      )

      assert_nil result
    end
  end

  test "notify after saving none still delivers nothing" do
    RecordingStudioNotifications::Preference.set!(
      recipient: @recipient,
      notification_type: :empty_channel_notify_test,
      channel: :in_app,
      enabled: false
    )

    assert_no_difference -> { RecordingStudioNotifications::Notification.where(recipient: @recipient).count } do
      result = RecordingStudioNotifications.notify(
        notification_type: :empty_channel_notify_test,
        recipient: @recipient,
        title: "Still quiet",
        channels: [:in_app],
        idempotency_key: "empty-channel-none-#{SecureRandom.uuid}"
      )

      assert_nil result
    end
  end

  test "notify delivers when an optional channel is enabled" do
    RecordingStudioNotifications::Preference.set!(
      recipient: @recipient,
      notification_type: :empty_channel_notify_test,
      channel: :in_app,
      enabled: true
    )

    notification = RecordingStudioNotifications.notify(
      notification_type: :empty_channel_notify_test,
      recipient: @recipient,
      title: "In app on",
      idempotency_key: "empty-channel-on-#{SecureRandom.uuid}"
    )

    assert_not_nil notification
    assert_equal ["in_app"], notification.deliveries.map(&:channel)
  end
end
