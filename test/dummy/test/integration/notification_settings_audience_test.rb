# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationSettingsAudienceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @member = User.create!(
      email: "member-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @staff = User.create!(
      email: "staff-#{SecureRandom.uuid}@staff.example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :staff_terms_settings_test,
      label: "Staff terms",
      category: :system,
      description: "Staff-only terms notices.",
      default_channels: [:in_app],
      available_channels: [:in_app],
      visible_to: ->(recipient) { recipient.email.end_with?("@staff.example.test") }
    )
  end

  test "settings hide staff kinds from members and ignore posted preferences for them" do
    sign_in @member

    get "/notifications/settings"

    assert_response :success
    refute_includes response.body, "Staff terms"

    patch "/notifications/settings", params: {
      preferences: { staff_terms_settings_test: ["in_app"] }
    }

    assert_redirected_to "/notifications/settings"
    assert_nil RecordingStudioNotifications::Preference.find_by(
      recipient: @member,
      notification_type: "staff_terms_settings_test",
      channel: "in_app"
    )
  end

  test "settings show staff kinds to matching recipients" do
    sign_in @staff

    get "/notifications/settings"

    assert_response :success
    assert_includes response.body, "Staff terms"
  end
end
