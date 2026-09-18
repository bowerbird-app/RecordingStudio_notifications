# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationSeedInboxTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    load Rails.root.join("db/seeds.rb").to_s
    @admin = User.find_by!(email: "admin@admin.com")
    sign_in @admin
  end

  test "seeded inbox mixes types, icons, and read state" do
    get "/notifications"

    assert_response :success
    assert_includes response.body, "Riley mentioned you just now"
    assert_includes response.body, "Getting Started needs a yes"
    assert_includes response.body, "Jo left a fresh note"
    assert_includes response.body, "New page: Getting Started"
    assert_includes response.body, "Workspace change"
    assert_includes response.body, "Page comment"
    assert_includes response.body, "Page created"
    assert_includes response.body, "System maintenance"
    refute_includes response.body, "System announcement 50"

    %w[at-symbol check-circle chat-bubble-left-ellipsis document-text bell exclamation-triangle].each do |icon|
      assert_includes response.body, "data-flat-pack--icon-name-value=\"#{icon}\""
    end

    assert_includes response.body, "fp-red-dot"
    assert_includes response.body, ">Clear all</span>"
  end
end
