# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationCadenceSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "cadence-settings-#{SecureRandom.uuid}@example.test") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
    RecordingStudioNotifications.notification_types.register(
      :settings_cadence_test,
      label: "Settings cadence test",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app],
      allowed_cadences: %i[individual daily weekly],
      default_cadence: :weekly
    )
    RecordingStudioNotifications.notification_types.register(
      :required_settings_cadence_test,
      label: "Required settings cadence test",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app],
      allowed_cadences: %i[daily weekly],
      default_cadence: :weekly,
      required_cadence: :daily
    )
    sign_in @user
  end

  test "settings render selectable and required notification cadence guidance" do
    get "/notifications/settings"

    assert_response :success
    assert_includes response.body, "Notification cadence"
    assert_includes response.body, "Controls when this notification type is delivered and how it is grouped in your inbox."
    assert_includes response.body, "This cadence is required for required settings cadence test."
    assert_includes response.body, "cadences[settings_cadence_test]"
    refute_includes response.body, "cadences[required_settings_cadence_test]"
  end

  test "settings persist an allowed cadence override independently of channels" do
    patch "/notifications/settings", params: {
      cadences: { settings_cadence_test: "daily" }
    }

    assert_redirected_to "/notifications/settings"
    assert_equal :daily, RecordingStudioNotifications::Preference.cadence_for(
      recipient: @user,
      notification_type: :settings_cadence_test,
      default: :weekly
    )
    assert_nil RecordingStudioNotifications::Preference.find_by(
      recipient: @user,
      notification_type: "settings_cadence_test",
      channel: :in_app
    )
  end
end