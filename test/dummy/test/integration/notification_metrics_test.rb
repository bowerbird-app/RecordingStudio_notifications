# frozen_string_literal: true

require "test_helper"

class NotificationMetricsTest < ActiveSupport::TestCase
  GrantContext = Struct.new(:access_grant)
  Grant = Struct.new(:actor)
  METRIC_IDENTIFIERS = %w[
    notifications.sent_over_time
    notifications.by_type
    notifications.read_vs_unread
    notification_deliveries.by_status
    notification_deliveries.by_channel
    notification_deliveries.failed_by_channel_over_time
  ].freeze
  WINDOW = { interval: "day", from: Time.utc(2026, 10, 6), to: Time.utc(2026, 10, 10) }.freeze

  setup do
    @staff = User.create!(
      email: "metrics-staff-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    @outsider = User.create!(
      email: "metrics-outsider-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    Current.actor = @staff
    @workspace = Workspace.create!(name: "Metrics #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @admin_root = RecordingStudio.root_recording_for(AdminRoot.first_or_create!)
    grant!(@admin_root, @staff, :admin)
    bootstrap_owner!(@root, @staff)
    seed_notifications!
    Current.actor = nil
  end

  teardown do
    Current.actor = nil
  end

  test "registered notification metrics return seeded type, read, and delivery values" do
    identifiers = RecordingStudioMetrics.definitions.map(&:identifier)
    METRIC_IDENTIFIERS.each { |identifier| assert_includes identifiers, identifier }

    sent = timeseries_counts(
      execute(
        "notifications.sent_over_time",
        interval: "day",
        start_at: Time.utc(2026, 10, 6),
        end_at: Time.utc(2026, 10, 10)
      )
    )
    assert_equal notifications_created_between(Time.utc(2026, 10, 7), Time.utc(2026, 10, 8)), sent["2026-10-07"]
    assert_equal notifications_created_between(Time.utc(2026, 10, 8), Time.utc(2026, 10, 9)), sent["2026-10-08"]
    assert_operator sent["2026-10-07"], :>=, 1
    assert_operator sent["2026-10-08"], :>=, 2

    type_counts = breakdown_counts(execute("notifications.by_type"))
    %w[page_comment mention].each do |type|
      assert_equal RecordingStudioNotifications::Notification.where(notification_type: type).count,
                   type_counts[type].to_i
    end

    read_state = breakdown_counts(execute("notifications.read_vs_unread"))
    assert_equal RecordingStudioNotifications::Notification.read.count, read_state["read"].to_i
    assert_equal RecordingStudioNotifications::Notification.unread.count, read_state["unread"].to_i
    assert_operator read_state["read"].to_i, :>=, 1
    assert_operator read_state["unread"].to_i, :>=, 1

    status_counts = breakdown_counts(execute("notification_deliveries.by_status"))
    RecordingStudioNotifications::Delivery::STATUSES.each do |status|
      assert_equal RecordingStudioNotifications::Delivery.where(status: status).count, status_counts[status].to_i
    end

    channel_counts = breakdown_counts(execute("notification_deliveries.by_channel"))
    %w[in_app email].each do |channel|
      assert_equal RecordingStudioNotifications::Delivery.where(channel: channel).count, channel_counts[channel].to_i
    end
  end

  test "failed deliveries over time bucket failed rows by updated_at and group by channel" do
    window = { interval: "day", start_at: Time.utc(2026, 10, 6), end_at: Time.utc(2026, 10, 10) }
    counts = timeseries_counts(execute("notification_deliveries.failed_by_channel_over_time", **window))
    expected = RecordingStudioNotifications::Delivery.failed
                                                      .where(updated_at: Time.utc(2026, 10, 8)...Time.utc(2026, 10, 9)).count
    assert_operator expected, :>=, 1
    assert_equal expected, counts["2026-10-08"]
    assert_equal 0, counts["2026-10-07"].to_i

    grouped = execute("notification_deliveries.failed_by_channel_over_time", **window, group_by: "channel")
    assert_equal "channel", grouped.group_by.to_s if grouped.respond_to?(:group_by)
    assert_raises(RecordingStudioMetrics::Errors::InvalidGroupBy) do
      execute("notification_deliveries.failed_by_channel_over_time", **window, group_by: "notification_id")
    end

    metadata = RecordingStudioMetrics.find("notification_deliveries.failed_by_channel_over_time").catalog_metadata
    assert_equal "count", metadata[:unit]
    assert_equal "Failed deliveries over time", metadata[:title]
    assert metadata[:description].present?
    assert_equal [:channel], metadata[:group_by]
    assert_equal 5, metadata[:min_group_size]
    assert metadata.dig(:date_range, :supported)
    assert_equal "UTC", metadata[:timezone]
  end

  test "api_authorize allows AdminRoot staff and denies non-admins" do
    %i[notifications notification_deliveries].each do |resource|
      authorize = RecordingStudioMetrics.registry.api_authorize_for(resource)
      assert_equal RecordingStudioNotifications::Metrics::AUTHORIZE, authorize

      assert authorize.call(GrantContext.new(Grant.new(@staff)))
      refute authorize.call(GrantContext.new(Grant.new(@outsider)))
      refute authorize.call(GrantContext.new(Grant.new(nil)))
    end
  end

  test "discovery lists each metric for AdminRoot staff and hides them from outsiders" do
    denied_ids = discover(@outsider).map { |row| row[:identifier] }
    allowed = discover(@staff)
    allowed_ids = allowed.map { |row| row[:identifier] }

    METRIC_IDENTIFIERS.each do |identifier|
      refute_includes denied_ids, identifier
      row = allowed.find { |metric| metric[:identifier] == identifier }

      assert row, "expected discovery entry for #{identifier}"
      assert_equal identifier, row[:identifier]
      assert_includes allowed_ids, identifier
    end

    failed = allowed.find { |metric| metric[:identifier] == "notification_deliveries.failed_by_channel_over_time" }
    assert_equal "count", failed[:unit]
    assert_equal [:channel], failed[:group_by]
    assert_equal 5, failed[:min_group_size]
    assert failed.dig(:date_range, :supported)
  end

  test "execute handler authorizes each metric for AdminRoot staff and denies outsiders" do
    METRIC_IDENTIFIERS.each do |identifier|
      resource, name = identifier.split(".", 2)
      payload = RecordingStudioMetrics::Api::ExecuteHandler.call(
        build_api_context(@staff, resource: resource, name: name)
      )

      assert_equal identifier, payload[:metric]
      assert_includes %i[timeseries breakdown], payload[:type]

      error = assert_raises(RecordingStudioMetrics::Errors::AuthorizationError) do
        RecordingStudioMetrics::Api::ExecuteHandler.call(
          build_api_context(@outsider, resource: resource, name: name)
        )
      end
      assert_equal "Not authorized to run this metric", error.public_message
    end
  end

  test "site resolver is preferred when it is set" do
    access_called = false
    with_admin_resolvers(
      site_resolver: ->(_context) { @admin_root },
      access_resolver: ->(_context) {
        access_called = true
        nil
      }
    ) do
      assert_equal @admin_root, RecordingStudioNotifications::Api::Access.admin_root_recording
      assert RecordingStudioNotifications::Api::Access.can_view?(GrantContext.new(Grant.new(@staff)))
      refute access_called
    end
  end

  test "access resolver is used when the site resolver is unset" do
    with_admin_resolvers(
      site_resolver: nil,
      access_resolver: ->(_context) { @admin_root }
    ) do
      assert_equal @admin_root, RecordingStudioNotifications::Api::Access.admin_root_recording
      assert RecordingStudioNotifications::Api::Access.can_view?(GrantContext.new(Grant.new(@staff)))
    end
  end

  test "a raising resolver denies the request" do
    with_admin_resolvers(
      site_resolver: ->(_context) { raise NoMethodError, "controller is nil" },
      access_resolver: ->(_context) { @admin_root }
    ) do
      assert_nothing_raised do
        refute RecordingStudioNotifications::Api::Access.can_view?(GrantContext.new(Grant.new(@staff)))
      end
    end
  end

  test "a resolver that returns nothing denies the request" do
    with_admin_resolvers(
      site_resolver: ->(_context) { nil },
      access_resolver: ->(_context) { @admin_root }
    ) do
      refute RecordingStudioNotifications::Api::Access.can_view?(GrantContext.new(Grant.new(@staff)))
    end
  end

  private

  def with_admin_resolvers(site_resolver:, access_resolver:)
    config = RecordingStudioAdmin.configuration
    original_site_resolver = config.site_admin_recording_resolver
    original_access_resolver = config.access_recording_resolver
    config.site_admin_recording_resolver = site_resolver
    config.access_recording_resolver = access_resolver
    yield
  ensure
    config.site_admin_recording_resolver = original_site_resolver
    config.access_recording_resolver = original_access_resolver
  end

  def execute(identifier, **params)
    RecordingStudioMetrics.execute(
      identifier,
      context: site_context,
      cache: false,
      **params
    )
  end

  def discover(actor)
    RecordingStudioMetrics::Api::DiscoveryHandler.call(build_api_context(actor)).fetch(:metrics)
  end

  def build_api_context(actor, resource: nil, name: nil)
    grant = Grant.new(actor)
    params = WINDOW.merge(
      resource: resource,
      name: name,
      start: nil,
      start_at: nil,
      end: nil,
      end_at: nil,
      timezone: "UTC",
      filters: {}
    )
    context = Object.new
    context.define_singleton_method(:access_grant) { grant }
    context.define_singleton_method(:api_client) { actor }
    context.define_singleton_method(:access_recording) { nil }
    context.define_singleton_method(:root_recording) { nil }
    context.define_singleton_method(:api_key) { :operations }
    context.define_singleton_method(:params) { params }
    context
  end

  def site_context
    RecordingStudioMetrics::Context.new(
      scope: :site,
      actor: @staff,
      site_authorized: true,
      timezone: "UTC"
    )
  end

  def seed_notifications!
    travel_to Time.utc(2026, 10, 7, 12) do
      create_notification(
        type: :page_comment,
        title: "October comment #{SecureRandom.hex(4)}",
        read_at: Time.current,
        deliveries: [{ channel: :in_app, status: "delivered" }]
      )
    end
    travel_to Time.utc(2026, 10, 8, 12) do
      create_notification(
        type: :mention,
        title: "October mention #{SecureRandom.hex(4)}",
        read_at: nil,
        deliveries: [
          { channel: :in_app, status: "pending" },
          { channel: :email, status: "failed" }
        ]
      )
      create_notification(
        type: :mention,
        title: "October mention two #{SecureRandom.hex(4)}",
        read_at: Time.current,
        deliveries: [{ channel: :email, status: "processing" }]
      )
    end
  end

  def create_notification(type:, title:, read_at:, deliveries:)
    notification = RecordingStudioNotifications::Notification.create!(
      notification_type: type,
      recipient: @outsider,
      actor: @staff,
      title: title,
      root_recording: type.to_s == "mention" ? nil : @root,
      read_at: read_at
    )
    deliveries.each do |attrs|
      notification.deliveries.create!(
        channel: attrs.fetch(:channel).to_s,
        status: attrs.fetch(:status)
      )
    end
    notification
  end

  def notifications_created_between(start_at, end_at)
    RecordingStudioNotifications::Notification.where(created_at: start_at...end_at).count
  end

  def breakdown_counts(result)
    result.data.to_h { |row| [row[:key].to_s, row[:value] || row["value"]] }
  end

  def timeseries_counts(result)
    result.data.to_h { |row| [(row[:date] || row["date"]).to_s, row[:value] || row["value"]] }
  end

  def bootstrap_owner!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: recording,
      actor: actor
    )
    raise result.error if result.failure?
  end

  def grant!(recording, actor, role)
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)

    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: @staff
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
