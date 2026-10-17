# frozen_string_literal: true

require "test_helper"

class DeliveryEmailMarksTest < ActiveSupport::TestCase
  setup do
    @recipient = User.create!(
      email: "email-marks-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :email_mark_optional,
      label: "Email mark optional",
      scope: :global,
      default_channels: [:email],
      available_channels: %i[in_app email]
    )
    RecordingStudioNotifications.notification_types.register(
      :email_mark_required,
      label: "Email mark required",
      scope: :global,
      default_channels: [:email],
      required_channels: [:email],
      available_channels: [:email]
    )
    @notification = RecordingStudioNotifications::Notification.create!(
      recipient: @recipient,
      notification_type: "email_mark_optional",
      title: "Optional email"
    )
    @delivery = @notification.deliveries.create!(
      channel: "email",
      status: "delivered",
      metadata: { "keep" => "yes" }
    )
  end

  test "each email mark stores its timestamp and keeps the first one" do
    opened_at = Time.utc(2026, 3, 1, 12, 0, 0)
    later = Time.utc(2026, 3, 2, 12, 0, 0)
    clicked_at = Time.utc(2026, 3, 3, 12, 0, 0)
    complained_at = Time.utc(2026, 3, 4, 12, 0, 0)

    @delivery.mark_email_opened!(at: opened_at)
    @delivery.mark_email_opened!(at: later)
    @delivery.mark_email_clicked!(at: clicked_at)
    @delivery.mark_email_complained!(at: complained_at)
    @delivery.reload

    assert_equal opened_at.iso8601, @delivery.metadata["email_opened_at"]
    assert_equal clicked_at.iso8601, @delivery.metadata["email_clicked_at"]
    assert_equal complained_at.iso8601, @delivery.metadata["email_complained_at"]
    assert_equal "yes", @delivery.metadata["keep"]
    assert @delivery.delivered?
  end

  test "unsubscribe stores the time and turns the email preference off" do
    at = Time.utc(2026, 4, 1, 8, 30, 0)

    @delivery.mark_email_unsubscribed!(at: at)

    assert_equal at.iso8601, @delivery.reload.metadata["email_unsubscribed_at"]
    assert_not RecordingStudioNotifications::Preference.enabled_for?(
      recipient: @recipient,
      notification_type: :email_mark_optional,
      channel: :email,
      default: true
    )
    assert @delivery.delivered?
  end

  test "bounce stores the time and leaves status alone" do
    at = Time.utc(2026, 5, 1, 9, 0, 0)
    @delivery.mark_email_bounced!(at: at)

    assert_equal at.iso8601, @delivery.reload.metadata["email_bounced_at"]
    assert @delivery.delivered?
    assert_nil @delivery.error_message

    failed = @notification.deliveries.create!(channel: "in_app", status: "failed", error_message: "job blew up")
    failed.mark_email_bounced!(at: at)
    failed.reload

    assert failed.failed?
    assert_equal "job blew up", failed.error_message
    assert_equal at.iso8601, failed.metadata["email_bounced_at"]
  end

  test "unsubscribe of a required email channel stores nothing" do
    notification = RecordingStudioNotifications::Notification.create!(
      recipient: @recipient,
      notification_type: "email_mark_required",
      title: "Required email"
    )
    delivery = notification.deliveries.create!(channel: "email", status: "delivered", metadata: {})

    assert_raises(ActiveRecord::RecordInvalid) do
      delivery.mark_email_unsubscribed!(at: Time.utc(2026, 6, 1, 10, 0, 0))
    end

    assert_nil delivery.reload.metadata["email_unsubscribed_at"]
    assert RecordingStudioNotifications::Preference.enabled_for?(
      recipient: @recipient,
      notification_type: :email_mark_required,
      channel: :email,
      default: true
    )
  end
end
