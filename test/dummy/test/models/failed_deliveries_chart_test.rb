# frozen_string_literal: true

require "test_helper"

class FailedDeliveriesChartTest < ActiveSupport::TestCase
  AdminContext = Struct.new(:current_actor, :access_recording, :root_recording, :timezone, keyword_init: true)

  setup do
    @staff = User.create!(
      email: "failed-chart-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    @recipient = User.create!(
      email: "failed-chart-recipient-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    @admin_root = RecordingStudio.root_recording_for(AdminRoot.first_or_create!)
    Current.actor = @staff
    notification = RecordingStudioNotifications::Notification.create!(
      notification_type: :mention,
      recipient: @recipient,
      actor: @staff,
      title: "Failed chart #{SecureRandom.hex(4)}"
    )
    notification.deliveries.create!(channel: "email", status: "failed")
    Current.actor = nil
    @context = AdminContext.new(
      current_actor: @staff,
      access_recording: @admin_root,
      root_recording: @admin_root,
      timezone: "UTC"
    )
  end

  teardown do
    Current.actor = nil
  end

  test "chart series and total read the failed deliveries metric grouped by channel" do
    chart = RecordingStudioNotifications::Admin::FailedDeliveriesChart
    result = chart.execute(@context)

    assert_equal "notification_deliveries.failed_by_channel_over_time", result.identifier
    assert_equal :channel, result.group_by.to_sym if result.respond_to?(:group_by) && result.group_by

    series = chart.series(@context)
    assert_kind_of Array, series
    refute_empty series
    series.each do |line|
      assert line[:name].present?
      assert_kind_of Array, line[:data]
    end
    assert_operator chart.total(@context), :>=, 1
  end

  test "failed deliveries widget links to the failed deliveries screen" do
    widget = RecordingStudioNotifications::Admin::FailedDeliveriesWidget
    screen = RecordingStudioNotifications::Admin::FailedDeliveriesScreen
    section = RecordingStudioNotifications::Admin::AllNotificationsSection

    assert_equal chart_widget_key, widget.key
    assert_equal chart_screen_key, screen.key
    assert_includes section.widget_keys, chart_widget_key
    assert_equal chart_screen_key, widget.link_to.call(path_context)
    assert_equal screen, RecordingStudioAdmin.screen_for(chart_screen_key)
    assert_equal widget, RecordingStudioAdmin.widget_for(chart_widget_key)
  end

  private

  def chart_widget_key
    RecordingStudioNotifications::Admin::FailedDeliveriesChart::WIDGET_KEY
  end

  def chart_screen_key
    RecordingStudioNotifications::Admin::FailedDeliveriesChart::SCREEN_KEY
  end

  def path_context
    context = Object.new
    context.define_singleton_method(:admin_screen_path) { |key| key }
    context
  end
end
