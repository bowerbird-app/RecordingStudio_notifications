# frozen_string_literal: true

require "test_helper"

class NotificationAccessDefaultsTest < ActiveSupport::TestCase
  setup do
    @recipient = User.create!(
      email: "access-defaults-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @other = User.create!(
      email: "access-defaults-other-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end

  test "view and preference defaults allow only the recipient" do
    assert authorized?(:view_notifications, actor: @recipient, recipient: @recipient)
    refute authorized?(:view_notifications, actor: @other, recipient: @recipient)
    refute authorized?(:view_notifications, actor: @recipient, recipient: nil)

    action = :"recording_studio_notifications.manage_preferences"
    assert authorized?(action, actor: @recipient, recipient: @recipient)
    refute authorized?(action, actor: @other, recipient: @recipient)
    refute authorized?(action, actor: nil, recipient: @recipient)
  end

  private

  def authorized?(action, actor:, recipient:)
    RecordingStudioAccessible.authorized_action?(
      actor: actor,
      action: action,
      context: { recipient: recipient }
    )
  end
end
