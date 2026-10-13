# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class BootOrderHostOverrideTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  HOST_TOOLTIP = "HOST This channel can't be removed"
  BOOT_HOST_LOCALE = Rails.root.join("config/locales/recording_studio_notifications_host.en.yml")
  OVERRIDE_KEY = "recording_studio.notifications.settings.required_channel_tooltip"

  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    sign_in @user
  end

  # Real-boot-order guard: host file under config/locales must win without any
  # test-time load_path mutation. Render assertion uses the required-channel tooltip
  # data attribute (hover-only chrome).
  test "host locale override for recording_studio.notifications wins on boot order" do
    assert_path_exists BOOT_HOST_LOCALE
    assert_equal HOST_TOOLTIP, I18n.t(OVERRIDE_KEY)

    get "/notifications/settings"

    assert_response :success
    assert_match(
      /required-channel-tooltip-value="HOST This channel can(&#39;|')t be removed"/,
      response.body
    )
    refute_match(
      /required-channel-tooltip-value="This channel can(&#39;|')t be removed"/,
      response.body
    )
  end
end
