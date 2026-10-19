# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class AdminFailedDeliveriesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    load Rails.root.join("db/seeds.rb")
    @user = User.find_by!(email: "admin@admin.com")
    sign_in @user
  end

  test "all notifications section renders the failed deliveries widget and link" do
    get "/admin/sections/all_notifications"

    assert_response :success
    assert_includes response.body, "Failed deliveries"
    assert_includes response.body, "See the chart"
    assert_includes response.body, "/admin/screens/recording_studio_notifications_failed_deliveries"
    refute_includes response.body, "translation missing"
  end

  test "failed deliveries screen renders the metric chart chrome" do
    get "/admin/screens/recording_studio_notifications_failed_deliveries"

    assert_response :success
    assert_includes response.body, "Failed deliveries"
    assert_includes response.body, "By channel, over time"
    refute_includes response.body, "translation missing"
  end
end
