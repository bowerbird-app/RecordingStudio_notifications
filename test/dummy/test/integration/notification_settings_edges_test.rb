# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationSettingsEdgesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      email: "settings-edges-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :settings_edge_mixed,
      label: "Settings edge mixed",
      scope: :global,
      default_channels: [:in_app],
      required_channels: [:in_app],
      available_channels: %i[in_app email],
      allowed_cadences: %i[individual daily],
      default_cadence: :individual
    )
    sign_in @user
  end

  test "mixed channels without a description still render the type" do
    get "/notifications/settings"

    assert_response :success
    assert_includes response.body, "Settings edge mixed"
    refute_includes response.body, "Required channels stay enabled and optional channels can be added or removed."
  end

  test "a cadence preference with a blank channel is skipped in the preference map" do
    RecordingStudioNotifications::Preference.set_cadence!(
      recipient: @user,
      notification_type: :settings_edge_mixed,
      cadence: :daily
    )

    get "/notifications/settings"

    assert_response :success
    assert_includes response.body, 'value="daily" selected="selected">Daily</option>'
  end

  test "an unknown cadence renders the settings form again" do
    patch "/notifications/settings", params: { cadences: { settings_edge_mixed: "hourly" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Settings edge mixed"
  end
end
