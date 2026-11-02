# frozen_string_literal: true

require "test_helper"

class NotificationUrlTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "open-url-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :open_url_notice,
      label: "Open URL notice",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    @notification = RecordingStudioNotifications.notify(
      notification_type: :open_url_notice,
      recipient: @user,
      title: "Open me #{SecureRandom.hex(4)}",
      deliver_later: false,
      idempotency_key: "open-url-#{SecureRandom.uuid}"
    )
  end

  test "notification_url is the absolute open route from mailer default_url_options" do
    url = RecordingStudioNotifications.notification_url(@notification)

    assert_equal "http://example.com/notifications/notifications/#{@notification.id}/open", url
    assert_equal url, RecordingStudioNotifications.notification_url(@notification.id)
  end
end
