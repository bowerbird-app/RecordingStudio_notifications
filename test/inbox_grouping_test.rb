# frozen_string_literal: true

require "test_helper"

class InboxGroupingTest < Minitest::Test
  FakeNotification = Struct.new(:id, :notification_type, :created_at, :read_at, keyword_init: true) do
    def unread?
      read_at.nil?
    end
  end

  def setup
    @original_configuration = RecordingStudioNotifications.instance_variable_get(:@configuration)
    RecordingStudioNotifications.reset_configuration!
    RecordingStudioNotifications.notification_types.register(
      :page_comment,
      label: "Page comments",
      allowed_cadences: %i[individual daily every_other_day weekly biweekly monthly],
      default_cadence: :weekly
    )
    RecordingStudioNotifications.notification_types.register(
      :workspace_change,
      label: "Workspace changes",
      allowed_cadences: %i[individual monthly],
      default_cadence: :monthly
    )
  end

  def teardown
    RecordingStudioNotifications.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_groups_by_notification_type_cadence_and_local_week
    notifications = [
      notification(id: "1", type: :page_comment, at: Time.utc(2026, 7, 13, 0, 30)),
      notification(id: "2", type: :page_comment, at: Time.utc(2026, 7, 12, 23, 30)),
      notification(id: "3", type: :workspace_change, at: Time.utc(2026, 7, 12, 22, 30))
    ]

    sections = grouping(notifications, time_zone: "America/Los_Angeles").call

    assert_equal %i[page_comment workspace_change], sections.map(&:notification_type)
    weekly_group = sections.first.groups.first
    assert_equal :weekly, weekly_group.cadence
    assert_equal Date.new(2026, 7, 6), weekly_group.period_starts_at.to_date
    assert_equal %w[1 2], weekly_group.notifications.map(&:id)
    assert_equal :monthly, sections.last.groups.first.cadence
  end

  def test_individual_cadence_never_creates_a_shared_group
    notifications = [
      notification(id: "1", type: :page_comment, at: Time.utc(2026, 7, 13, 12)),
      notification(id: "2", type: :page_comment, at: Time.utc(2026, 7, 13, 11))
    ]

    groups = grouping(notifications, cadence: :individual).call.first.groups

    assert_equal 2, groups.size
    assert groups.all?(&:individual?)
    assert_equal [1, 1], groups.map { |group| group.notifications.size }
  end

  def test_stable_two_day_and_biweekly_periods_use_fixed_anchors
    two_day_notifications = [
      notification(id: "1", type: :page_comment, at: Time.utc(2026, 7, 13, 12)),
      notification(id: "2", type: :page_comment, at: Time.utc(2026, 7, 14, 12))
    ]
    biweekly_notifications = [
      notification(id: "3", type: :page_comment, at: Time.utc(2026, 7, 12, 12)),
      notification(id: "4", type: :page_comment, at: Time.utc(2026, 7, 13, 12))
    ]

    two_day_groups = grouping(two_day_notifications, cadence: :every_other_day).call.first.groups
    biweekly_groups = grouping(biweekly_notifications, cadence: :biweekly).call.first.groups

    assert_equal 2, two_day_groups.size
    assert_equal 1, biweekly_groups.size
    assert_equal Date.new(2026, 7, 6), biweekly_groups.first.period_starts_at.to_date
  end

  def test_group_heading_derives_unread_state_from_source_notifications
    notifications = [
      notification(id: "1", type: :page_comment, at: Time.utc(2026, 7, 13, 12)),
      FakeNotification.new(id: "2", notification_type: "page_comment", created_at: Time.utc(2026, 7, 13, 11), read_at: Time.utc(2026, 7, 13, 12))
    ]

    group = grouping(notifications, cadence: :daily).call.first.groups.first

    assert_equal 1, group.unread_count
    assert_includes group.heading, "1 unread"

    notifications.each { |notification| notification.read_at = Time.utc(2026, 7, 13, 13) }

    assert_equal 0, group.unread_count
    assert_includes group.heading, "All read"
  end

  def test_period_labels_are_compact_and_cadence_aware
    daily_group = grouping(
      [notification(id: "1", type: :page_comment, at: Time.utc(2026, 7, 3, 12))],
      cadence: :daily
    ).call.first.groups.first
    weekly_group = grouping(
      [notification(id: "2", type: :page_comment, at: Time.utc(2026, 7, 8, 12))],
      cadence: :weekly
    ).call.first.groups.first
    monthly_group = grouping(
      [notification(id: "3", type: :workspace_change, at: Time.utc(2026, 7, 8, 12))],
      cadence: :monthly
    ).call.first.groups.first

    assert_equal "Jul 3", daily_group.period_label
    assert_equal "Jul 6 – Jul 12", weekly_group.period_label
    assert_equal "Jul 2026", monthly_group.period_label
  end

  def test_legacy_type_definition_without_cadence_metadata_defaults_to_individual
    legacy_type = Struct.new(:key, :label).new(:legacy_notification, "Legacy notifications")
    registry = RecordingStudioNotifications.notification_types
    registry.instance_variable_get(:@types)[:legacy_notification] = legacy_type
    notifications = [
      notification(id: "1", type: :legacy_notification, at: Time.utc(2026, 7, 13, 12)),
      notification(id: "2", type: :legacy_notification, at: Time.utc(2026, 7, 13, 11))
    ]

    groups = RecordingStudioNotifications::Services::InboxGrouping.new(
      recipient: Object.new,
      notifications: notifications,
      time_zone: "UTC"
    ).call.first.groups

    assert_equal 2, groups.size
    assert groups.all?(&:individual?)
  end

  private

  def grouping(notifications, time_zone: "UTC", cadence: nil)
    RecordingStudioNotifications::Services::InboxGrouping.new(
      recipient: Object.new,
      notifications: notifications,
      time_zone: time_zone,
      cadence_resolver: ->(_notification, type) { cadence || type.default_cadence }
    )
  end

  def notification(id:, type:, at:)
    FakeNotification.new(id: id, notification_type: type.to_s, created_at: at, read_at: nil)
  end
end