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
    @failed = notification.deliveries.create!(
      channel: "email",
      status: "failed",
      error_message: "provider unavailable"
    )
    @delivered = notification.deliveries.create!(channel: "in_app", status: "delivered")
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

  test "chart series points are x/y hashes and the total reads failed deliveries by channel" do
    chart = RecordingStudioNotifications::Admin::FailedDeliveriesChart
    result = chart.execute(@context)

    assert_equal "notification_deliveries.failed_by_channel_over_time", result.metric
    assert_equal :channel, result.group_by.to_sym if result.respond_to?(:group_by) && result.group_by

    series = chart.series(@context)
    assert_kind_of Array, series
    refute_empty series
    series.each do |line|
      assert line[:name].present?
      assert_kind_of Array, line[:data]
      refute_empty line[:data]
      line[:data].each do |point|
        assert_kind_of Hash, point
        assert point.key?(:x)
        assert point.key?(:y)
        refute_kind_of Array, point
        assert_kind_of Numeric, point[:y]
      end
    end
    assert series.any? { |line| line[:data].any? { |point| point[:y].positive? } }
    assert_operator chart.total(@context), :>=, 1
  end

  test "failed deliveries widget links to the failed deliveries screen" do
    widget = RecordingStudioNotifications::Admin::FailedDeliveriesWidget
    screen = RecordingStudioNotifications::Admin::FailedDeliveriesScreen
    section = RecordingStudioNotifications::Admin::AllNotificationsSection

    assert_equal chart_widget_key, widget.key
    assert_equal chart_screen_key, screen.key
    assert_includes section.widget_keys, chart_widget_key
    refute_includes screen.widget_keys, chart_widget_key
    table_link = section.links.find { |link| link.name == :notifications_table }
    assert table_link
    style = table_link.respond_to?(:style) ? table_link.style : table_link.instance_variable_get(:@style)
    refute_equal :primary, style
    assert(section.links.any? { |link| link.name == :failed_deliveries })
    assert_equal chart_screen_key, widget.link_to.call(path_context)
    assert_equal screen, RecordingStudioAdmin.screen_for(chart_screen_key)
    assert_equal widget, RecordingStudioAdmin.widget_for(chart_widget_key)
  end

  test "failed deliveries table reads stored delivery rows and filters by channel and kind" do
    screen = RecordingStudioNotifications::Admin::FailedDeliveriesScreen
    relation = screen.query.call(nil)
    kind = screen.filters.find { |filter| filter.key == :kind }
    channel = screen.filters.find { |filter| filter.key == :channel }

    assert_includes relation, @failed
    refute_includes relation, @delivered
    assert_equal :inline, screen.filter_presentation
    assert_equal %i[date_range group_by channel kind], screen.filters.map(&:key)

    columns = screen.table.columns.index_by(&:key)
    assert_equal @recipient.email, columns.fetch(:recipient).value.call(@failed, nil)
    assert_equal "provider unavailable", columns.fetch(:error_message).value.call(@failed, nil)

    by_kind = kind.apply(relation, "mention", nil)
    assert_includes by_kind, @failed
    refute_includes kind.apply(relation, "page_comment", nil), @failed

    by_channel = channel.apply(relation, "email", nil)
    assert_includes by_channel, @failed
    refute_includes channel.apply(relation, "in_app", nil), @failed
  end

  test "failed deliveries recipient column uses email, falls back, and preloads recipients" do
    screen = RecordingStudioNotifications::Admin::FailedDeliveriesScreen
    second = User.create!(
      email: "failed-chart-recipient-2-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    Current.actor = @staff
    other = RecordingStudioNotifications::Notification.create!(
      notification_type: :mention,
      recipient: second,
      actor: @staff,
      title: "Failed chart #{SecureRandom.hex(4)}"
    ).deliveries.create!(channel: "email", status: "failed", error_message: "timeout")
    Current.actor = nil

    loaded = screen.query.call(nil).where(id: [@failed.id, other.id]).to_a
    assert(loaded.all? { |row| row.association(:notification).loaded? })
    assert(loaded.all? { |row| row.notification.association(:recipient).loaded? })

    query_count = 0
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      next if payload[:cached]
      next if payload[:name].to_s.include?("SCHEMA")

      query_count += 1
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      loaded.each { |row| screen.class.recipient_label_for(row) }
    end
    assert_equal 0, query_count

    missing = Struct.new(:notification).new(
      Struct.new(:recipient, :recipient_type, :recipient_id).new(Object.new, "User", 99)
    )
    blank = Struct.new(:notification).new(
      Struct.new(:recipient, :recipient_type, :recipient_id).new(
        Struct.new(:email).new(""),
        "User",
        7
      )
    )
    assert_equal "User #99", screen.class.recipient_label_for(missing)
    assert_equal "User #7", screen.class.recipient_label_for(blank)
  end

  test "failed deliveries screen chart uses the filtered table scope and group by interval" do
    chart = RecordingStudioNotifications::Admin::FailedDeliveriesChart
    screen = RecordingStudioNotifications::Admin::FailedDeliveriesScreen
    relation = screen.filter_kind(screen.query.call(nil), "mention", nil)
    context = ScreenChartContext.new(relation: relation, group_by: :week)

    series = chart.screen_series(context)
    assert_kind_of Array, series
    refute_empty series
    series.each do |line|
      assert line[:name].present?
      line[:data].each do |point|
        assert_kind_of Hash, point
        assert point.key?(:x)
        assert_kind_of Numeric, point[:y]
      end
    end
    assert_equal 1, series.sum { |line| line[:data].sum { |point| point[:y] } }

    empty = chart.screen_series(ScreenChartContext.new(
      relation: screen.filter_kind(screen.query.call(nil), "page_comment", nil),
      group_by: :month
    ))
    assert_equal 0, empty.sum { |line| line[:data].sum { |point| point[:y] } }
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

  class ScreenChartContext
    def initialize(relation:, group_by: :day)
      @relation = relation
      @group_by = group_by
    end

    def query_result
      Struct.new(:relation).new(@relation)
    end

    def filter_value(key)
      key.to_sym == :group_by ? @group_by : nil
    end
  end
end
