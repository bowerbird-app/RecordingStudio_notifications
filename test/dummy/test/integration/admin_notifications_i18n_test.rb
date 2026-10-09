# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminNotificationsI18nTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    load Rails.root.join("db/seeds.rb")
    @user = User.find_by!(email: "admin@admin.com")
    sign_in @user
  end

  test "admin all notifications screen renders literal English chrome" do
    get "/admin/screens/recording_studio_notifications_all_notifications"

    assert_response :success
    assert_includes response.body, "All notifications"
    assert_includes response.body, "Root-scoped and global notification overview"
    assert_includes response.body, ">Type<"
    assert_includes response.body, ">Scope<"
    assert_includes response.body, ">Status<"
    refute_includes response.body, "translation missing"
  end

  test "admin all notifications section renders open table link in English" do
    get "/admin/sections/all_notifications"

    assert_response :success
    assert_includes response.body, "All notifications"
    assert_includes response.body, "Root-scoped and global notification overview"
    assert_includes response.body, "Open notifications table"
    refute_includes response.body, "translation missing"
  end
end
