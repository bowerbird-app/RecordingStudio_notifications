# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class HostLocaleOverrideTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "host-override@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    sign_in @user
  end

  test "host locale file overrides gem English on a real notifications page" do
    override_path = Rails.root.join("config/locales/en.notifications_host_override.yml")

    assert_path_exists override_path
    refute_includes File.read(override_path), "I18n.load_path"
    refute(
      I18n.load_path.any? { |path| path.to_s.end_with?("en.notifications_host_override.yml") && path.to_s.include?("tmp") },
      "override must come from dummy config/locales, not a temporary load_path append"
    )

    get "/notifications"

    assert_response :success
    assert_includes response.body, "Host says the inbox is empty"
    refute_includes response.body, "No notifications yet."
  end
end
