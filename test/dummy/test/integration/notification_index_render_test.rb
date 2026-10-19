# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationIndexRenderTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      email: "inbox-render-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    sign_in @user
  end

  test "notifications index and inbox root render" do
    get "/notifications/notifications"

    assert_response :success
    assert_includes response.body, "border-2 border-[var(--card-border-color)]"

    get "/notifications"

    assert_response :success
    assert_includes response.body, "border-2 border-[var(--card-border-color)]"
    assert_includes response.body, ">Notifications</h1>"

    get "/"

    assert_response :success
    ["Try it", "FlatPack usage"].each do |title|
      assert_select ".fp-card", text: /#{Regexp.escape(title)}/ do |cards|
        assert_equal 1, cards.size
        assert_includes cards.first["class"], "border-2 border-[var(--card-border-color)]"
      end
    end
  end
end
