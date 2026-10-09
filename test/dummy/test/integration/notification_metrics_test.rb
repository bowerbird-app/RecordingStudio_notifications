# frozen_string_literal: true

require "test_helper"

class NotificationMetricsTest < ActiveSupport::TestCase
  GrantContext = Struct.new(:access_grant)
  Grant = Struct.new(:actor)

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
    %w[
      notifications.sent_over_time
      notifications.by_type
      notifications.read_vs_unread
      notification_deliveries.by_status
      notification_deliveries.by_channel
    ].each { |identifier| assert_includes identifiers, identifier }

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

  test "api_authorize allows AdminRoot staff and denies non-admins" do
    authorize = RecordingStudioMetrics.registry.api_authorize_for(:notifications)
    assert_equal RecordingStudioNotifications::Metrics::AUTHORIZE, authorize

    assert authorize.call(GrantContext.new(Grant.new(@staff)))
    refute authorize.call(GrantContext.new(Grant.new(@outsider)))
    refute authorize.call(GrantContext.new(Grant.new(nil)))
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
