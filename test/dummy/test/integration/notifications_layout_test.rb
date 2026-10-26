# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationsLayoutTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      email: "layout-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    sign_in @user
    @notifications_layout = RecordingStudioNotifications.configuration.layout
    @studio_layout = RecordingStudio.configuration.layout
  end

  teardown do
    RecordingStudioNotifications.configuration.layout = @notifications_layout
    RecordingStudio.configuration.layout = @studio_layout
  end

  test "a nil layout uses the recording studio layout and then the default template" do
    RecordingStudioNotifications.configuration.layout = nil
    RecordingStudio.configuration.layout = "application"

    get "/notifications"

    assert_response :success
    assert_select "body[data-recording-studio-default-layout]", count: 0
    assert_includes response.body, "max-w-md"

    RecordingStudio.configuration.layout = nil

    get "/notifications"

    assert_response :success
    assert_select "body[data-recording-studio-default-layout=true]", count: 1
    assert_select "h1", text: "Notifications", count: 1
    assert_select "header nav[aria-label='Page navigation']", count: 1
  end

  test "a string layout name is used as the page shell" do
    RecordingStudioNotifications.configuration.layout = "application"

    get "/notifications"

    assert_response :success
    assert_select "body[data-recording-studio-default-layout]", count: 0
    assert_includes response.body, "max-w-md"
  end

  test "false skips the layout" do
    RecordingStudioNotifications.configuration.layout = false

    get "/notifications"

    assert_response :success
    assert_select "body[data-recording-studio-default-layout]", count: 0
    assert_select "h1", count: 0
  end

  test "a keyword callable chooses the layout" do
    RecordingStudioNotifications.configuration.layout = ->(controller:) do
      assert_kind_of ActionController::Base, controller
      "recording_studio/default_layout"
    end

    get "/notifications"

    assert_response :success
    assert_select "body[data-recording-studio-default-layout=true]", count: 1
    assert_select "h1", text: "Notifications", count: 1
  end
end
