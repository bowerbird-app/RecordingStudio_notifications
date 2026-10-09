# frozen_string_literal: true

require "test_helper"

class NotificationMetricsApiTest < ActionDispatch::IntegrationTest
  OPERATIONS_ROOT = "/recording_studio_api/apis/operations/v1"
  PUBLIC_ROOT = "/recording_studio_api/api/v1"

  setup do
    @staff = User.create!(
      email: "metrics-staff-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    @patron = User.create!(
      email: "metrics-patron-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    Current.actor = @staff
    @workspace = Workspace.create!(name: "Metrics #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @admin_root = RecordingStudio.root_recording_for(AdminRoot.first_or_create!)
    grant!(@admin_root, @staff, :admin)
    bootstrap_owner!(@root, @staff)
    grant!(@root, @patron, :edit)

    seed_notifications!

    @staff_operations_token = provision_token(
      access_point: @admin_root,
      actor: @staff,
      role: :edit,
      name: "Staff operations metrics #{SecureRandom.hex(4)}",
      api: :operations
    )
    @workspace_operations_token = provision_token(
      access_point: @root,
      actor: @staff,
      role: :edit,
      name: "Workspace operations metrics #{SecureRandom.hex(4)}",
      api: :operations
    )
    @public_token = provision_token(
      access_point: @root,
      actor: @staff,
      role: :view,
      name: "Public metrics #{SecureRandom.hex(4)}"
    )
    Current.actor = nil
  end

  teardown do
    Current.actor = nil
  end

  test "operations staff token reads notification and delivery metrics" do
    get "#{OPERATIONS_ROOT}/metrics/notifications/sent_over_time",
        params: { interval: "day" },
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    sent = timeseries_counts(response.parsed_body)
    assert_equal notifications_created_between(Time.utc(2026, 2, 10), Time.utc(2026, 2, 11)), sent["2026-02-10"]
    assert_equal notifications_created_between(Time.utc(2026, 2, 11), Time.utc(2026, 2, 12)), sent["2026-02-11"]
    assert_operator sent["2026-02-10"], :>=, 1
    assert_operator sent["2026-02-11"], :>=, 2

    get "#{OPERATIONS_ROOT}/metrics/notifications/by_type",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    type_counts = breakdown_counts(response.parsed_body)
    %w[page_comment mention].each do |type|
      assert_equal RecordingStudioNotifications::Notification.where(notification_type: type).count,
                   type_counts[type].to_i
    end

    get "#{OPERATIONS_ROOT}/metrics/notifications/read_vs_unread",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    read_state = breakdown_counts(response.parsed_body)
    assert_equal RecordingStudioNotifications::Notification.read.count, read_state["read"].to_i
    assert_equal RecordingStudioNotifications::Notification.unread.count, read_state["unread"].to_i
    assert_operator read_state["read"].to_i, :>=, 1
    assert_operator read_state["unread"].to_i, :>=, 1

    get "#{OPERATIONS_ROOT}/metrics/notification_deliveries/by_status",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    status_counts = breakdown_counts(response.parsed_body)
    RecordingStudioNotifications::Delivery::STATUSES.each do |status|
      assert_equal RecordingStudioNotifications::Delivery.where(status: status).count, status_counts[status].to_i
    end

    get "#{OPERATIONS_ROOT}/metrics/notification_deliveries/by_channel",
        headers: auth(@staff_operations_token),
        as: :json
    assert_response :success
    channel_counts = breakdown_counts(response.parsed_body)
    %w[in_app email].each do |channel|
      assert_equal RecordingStudioNotifications::Delivery.where(channel: channel).count, channel_counts[channel].to_i
    end
  end

  test "metrics index lists notification metrics" do
    get "#{OPERATIONS_ROOT}/metrics", headers: auth(@staff_operations_token), as: :json

    assert_response :success
    identifiers = response.parsed_body.fetch("metrics").map { |row| row.fetch("identifier") }
    %w[
      notifications.sent_over_time
      notifications.by_type
      notifications.read_vs_unread
      notification_deliveries.by_status
      notification_deliveries.by_channel
    ].each { |identifier| assert_includes identifiers, identifier }
  end

  test "non-admin operations token is denied notification metrics" do
    get "#{OPERATIONS_ROOT}/metrics/notifications/by_type",
        headers: auth(@workspace_operations_token),
        as: :json
    assert_response :forbidden

    get "#{OPERATIONS_ROOT}/metrics/notification_deliveries/by_status",
        headers: auth(@workspace_operations_token),
        as: :json
    assert_response :forbidden

    get "#{OPERATIONS_ROOT}/metrics", headers: auth(@workspace_operations_token), as: :json
    assert_response :success
    identifiers = response.parsed_body.fetch("metrics").map { |row| row.fetch("identifier") }
    refute_includes identifiers, "notifications.by_type"
    refute_includes identifiers, "notification_deliveries.by_status"
  end

  test "public API token is denied operations notification metrics" do
    get "#{OPERATIONS_ROOT}/metrics/notifications/by_type",
        headers: auth(@public_token),
        as: :json
    assert_response :unauthorized

    get "#{OPERATIONS_ROOT}/metrics/notification_deliveries/by_channel",
        headers: auth(@public_token),
        as: :json
    assert_response :unauthorized

    get "#{PUBLIC_ROOT}/metrics/notifications/by_type",
        headers: auth(@public_token),
        as: :json
    assert_includes [404, 401, 403], response.status
  end

  private

  def seed_notifications!
    travel_to Time.utc(2026, 2, 10, 12) do
      create_notification(
        type: :page_comment,
        title: "February comment #{SecureRandom.hex(4)}",
        read_at: Time.current,
        deliveries: [{ channel: :in_app, status: "delivered" }]
      )
    end
    travel_to Time.utc(2026, 2, 11, 12) do
      create_notification(
        type: :mention,
        title: "March mention #{SecureRandom.hex(4)}",
        read_at: nil,
        deliveries: [
          { channel: :in_app, status: "pending" },
          { channel: :email, status: "failed" }
        ]
      )
      create_notification(
        type: :mention,
        title: "March mention two #{SecureRandom.hex(4)}",
        read_at: Time.current,
        deliveries: [{ channel: :email, status: "processing" }]
      )
    end
  end

  def create_notification(type:, title:, read_at:, deliveries:)
    notification = RecordingStudioNotifications::Notification.create!(
      notification_type: type,
      recipient: @patron,
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

  def breakdown_counts(payload)
    payload.fetch("data").to_h { |row| [row.fetch("key").to_s, row.fetch("value")] }
  end

  def notifications_created_between(start_at, end_at)
    RecordingStudioNotifications::Notification.where(created_at: start_at...end_at).count
  end

  def timeseries_counts(payload)
    payload.fetch("data").to_h { |row| [row.fetch("date").to_s, row.fetch("value")] }
  end

  def auth(token)
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end

  def provision_token(access_point:, actor:, role:, name:, api: :public)
    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point,
      manager_actor: actor,
      role: role,
      name: name,
      api: api
    )
    raise result.error unless result.success?

    payload = result.value
    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token),
      api: api
    )
    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
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
