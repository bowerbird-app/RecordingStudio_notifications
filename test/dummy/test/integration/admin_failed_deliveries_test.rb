# frozen_string_literal: true

require "test_helper"
require "cgi"
require "json"
require "devise/test/integration_helpers"

class AdminFailedDeliveriesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    load Rails.root.join("db/seeds.rb")
    @user = User.find_by!(email: "admin@admin.com")
    sign_in @user
  end

  test "all notifications section renders the failed deliveries widget without a see the chart button" do
    get "/admin/sections/all_notifications"

    assert_response :success
    assert_includes response.body, "Failed deliveries"
    refute_includes response.body, "See the chart"
    refute_includes response.body, "translation missing"
  end

  test "failed deliveries screen renders the failed delivery table and filters" do
    recipient = create_failed_delivery_recipient

    get "/admin/screens/recording_studio_notifications_failed_deliveries"

    assert_response :success
    assert_includes response.body, "Failed deliveries"
    assert_includes response.body, "Sends that are still failed"
    assert_includes response.body, ">Time<"
    assert_includes response.body, ">Recipient<"
    assert_includes response.body, ">Channel<"
    assert_includes response.body, ">Error<"
    assert_includes response.body, recipient.email
    assert_includes response.body, 'data-recording-studio-admin--screen-filters-modal-filters-value="false"'
    refute_includes response.body, 'data-recording-studio-admin--screen-filters-modal-filters-value="true"'
    %w[hour day week month year].each { |bucket| assert_match(/\b#{bucket}\b/, response.body) }
    refute_includes response.body, "See the chart"
    refute_includes response.body, "translation missing"

    get "/admin/screens/recording_studio_notifications_failed_deliveries",
        headers: { "Turbo-Frame" => "screen-chart" }

    assert_response :success
    assert_admin_chart_xy_series(response.body)
  end

  test "all notifications widget series uses x/y hashes for the admin chart" do
    get "/admin/sections/all_notifications/widgets/#{chart_widget_key}"

    assert_response :success
    assert_admin_chart_xy_series(response.body)
  end

  private

  def chart_widget_key
    RecordingStudioNotifications::Admin::FailedDeliveriesChart::WIDGET_KEY
  end

  def create_failed_delivery_recipient
    recipient = User.create!(
      email: "failed-admin-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    Current.actor = @user
    notification = RecordingStudioNotifications::Notification.create!(
      notification_type: :mention,
      recipient: recipient,
      actor: @user,
      title: "Failed admin #{SecureRandom.hex(4)}"
    )
    notification.deliveries.create!(channel: "email", status: "failed", error_message: "provider unavailable")
    Current.actor = nil
    recipient
  end

  def assert_admin_chart_xy_series(html)
    body = CGI.unescapeHTML(html)
    match = body.match(/data-flat-pack--chart-series-value="(\[\{.*\}\])"/m)
    assert match, "expected a Flatpack chart series payload"

    series = JSON.parse(match[1])
    assert_kind_of Array, series
    refute_empty series

    series.each do |line|
      assert line["name"].present?
      data = line.fetch("data")
      assert_kind_of Array, data
      data.each do |point|
        assert_kind_of Hash, point, "admin line charts expect {x, y} hashes, not [date, value] tuples"
        assert point.key?("x")
        assert point.key?("y")
        assert_kind_of Numeric, point["y"]
      end
    end
  end
end
