# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require "yaml"

class HostLocaleOverrideTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  HOST_EMPTY = "Host says the inbox is empty"
  OVERRIDE_PATH = Rails.root.join("test/locales/host_override.en.yml")

  setup do
    @user = User.find_or_create_by!(email: "host-override@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    sign_in @user
  end

  test "host locale override wins over gem English on a real notifications page" do
    assert_path_exists OVERRIDE_PATH
    refute_includes OVERRIDE_PATH.to_s, "config/locales",
                    "override must stay test-only so the default dummy UI keeps gem English"

    original_load_path = I18n.load_path.dup
    translations = YAML.safe_load_file(OVERRIDE_PATH, aliases: true).fetch("en")
    I18n.backend.store_translations(:en, translations)

    get "/notifications"

    assert_response :success
    assert_includes response.body, HOST_EMPTY
    refute_includes response.body, "No notifications yet."
  ensure
    I18n.load_path.replace(original_load_path) if original_load_path
    I18n.backend.reload!
  end

  test "default dummy UI still shows gem English when no test override is loaded" do
    get "/notifications"

    assert_response :success
    assert_includes response.body, "No notifications yet."
    refute_includes response.body, HOST_EMPTY
  end
end
