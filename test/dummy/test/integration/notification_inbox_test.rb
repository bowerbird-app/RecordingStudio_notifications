# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationInboxTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      email: "inbox-flag-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :inbox_skip_notice,
      label: "Inbox skip notice",
      scope: :global,
      inbox: false,
      default_channels: %i[in_app email],
      available_channels: %i[in_app email],
      allowed_cadences: [:individual],
      default_cadence: :individual
    )
    RecordingStudioNotifications.notification_types.register(
      :inbox_visible_notice,
      label: "Inbox visible notice",
      scope: :global,
      default_channels: %i[in_app email],
      available_channels: %i[in_app email],
      allowed_cadences: [:individual],
      default_cadence: :individual
    )
    RecordingStudioNotifications.notification_types.register(
      :inbox_required_in_app,
      label: "Inbox required in app",
      scope: :global,
      default_channels: [:in_app],
      required_channels: [:in_app],
      available_channels: %i[in_app email],
      allowed_cadences: [:individual],
      default_cadence: :individual
    )
    sign_in @user
  end

  test "a type default of inbox false is overridden per call and stays out of the inbox" do
    hidden = notify(:inbox_skip_notice, title: "Email only hidden", inbox: nil)
    shown = notify(:inbox_skip_notice, title: "Forced into the inbox", inbox: true)
    column = RecordingStudioNotifications::Notification.columns_hash.fetch("inbox")

    assert_equal false, hidden.inbox
    assert_equal ["email"], hidden.deliveries.pluck(:channel)
    assert_equal true, shown.inbox
    assert_equal %w[email in_app], shown.deliveries.pluck(:channel).sort
    assert_equal false, column.null
    assert_equal true, ActiveModel::Type::Boolean.new.cast(column.default)

    get "/notifications"
    assert_response :success
    assert_includes response.body, "Forced into the inbox"
    refute_includes response.body, "Email only hidden"

    get "/notifications/notifications/menu.json"
    payload = JSON.parse(response.body)
    titles = payload.fetch("notifications").map { |item| item["title"] }
    assert_includes titles, "Forced into the inbox"
    refute_includes titles, "Email only hidden"
    assert_equal 1, payload.fetch("unread_count")

    get "/notifications/notifications/#{hidden.id}"
    assert_response :not_found

    get "/notifications/notifications/groups/notification-group-inbox_skip_notice-individual-#{hidden.id}/page"
    assert_response :not_found

    get "/notifications/notifications/#{hidden.id}/open"
    assert_response :redirect
    assert hidden.reload.read?

    relation = RecordingStudioNotifications::Admin::AllNotificationsScreen.query.call(nil)
    assert_includes relation, hidden
  end

  test "member actions and clear all ignore a hidden row" do
    hidden = notify(:inbox_visible_notice, title: "Hidden from clear", inbox: false)
    visible = notify(:inbox_visible_notice, title: "Visible clear target", inbox: true)

    %w[mark_read mark_unread archive unarchive].each do |action|
      patch "/notifications/notifications/#{hidden.id}/#{action}"
      assert_response :not_found
    end
    hidden.reload
    assert hidden.unread?
    refute hidden.archived?

    patch "/notifications/notifications/clear_all"
    assert_response :see_other
    assert visible.reload.cleared_at.present?
    assert_nil hidden.reload.cleared_at
  end

  test "required in-app plus inbox false writes nothing" do
    assert_no_difference -> { RecordingStudioNotifications::Notification.count } do
      assert_no_difference -> { RecordingStudioNotifications::Delivery.count } do
        error = assert_raises(ArgumentError) do
          notify(:inbox_required_in_app, title: "Should not persist", inbox: false)
        end
        assert_equal "inbox cannot be false when in_app is a required channel", error.message
      end
    end
  end

  test "an idempotent replay keeps the original inbox flag and channels" do
    key = "inbox-replay-#{SecureRandom.uuid}"
    first = notify(:inbox_visible_notice, title: "First write", inbox: false, idempotency_key: key)
    second = notify(:inbox_visible_notice, title: "Second write", inbox: true, idempotency_key: key,
                                            channels: %i[in_app email])

    assert_equal first.id, second.id
    assert_equal false, first.reload.inbox
    assert_equal ["email"], first.deliveries.pluck(:channel)

    required_key = "inbox-required-replay-#{SecureRandom.uuid}"
    required = notify(:inbox_required_in_app, title: "Required first", inbox: true, idempotency_key: required_key)
    replay = notify(:inbox_required_in_app, title: "Required retry", inbox: false, idempotency_key: required_key)

    assert_equal required.id, replay.id
    assert_equal true, required.reload.inbox
    assert_includes required.deliveries.pluck(:channel), "in_app"
  end

  test "read vs unread and sent metrics count a hidden unread row" do
    hidden = notify(:inbox_visible_notice, title: "Counted while hidden", inbox: false)
    context = RecordingStudioMetrics::Context.new(
      scope: :site,
      actor: @user,
      site_authorized: true,
      timezone: "UTC"
    )
    read_state = breakdown_counts(
      RecordingStudioMetrics.execute("notifications.read_vs_unread", context: context, cache: false)
    )

    assert hidden.unread?
    assert_equal false, hidden.inbox
    assert_equal RecordingStudioNotifications::Notification.unread.count, read_state.fetch("unread")

    start_at = Time.current.beginning_of_day
    sent = timeseries_total(
      RecordingStudioMetrics.execute(
        "notifications.sent_over_time",
        context: context,
        cache: false,
        interval: "day",
        start_at: start_at,
        end_at: start_at + 1.day
      )
    )
    expected = RecordingStudioNotifications::Notification.where(created_at: start_at...(start_at + 1.day)).count
    assert_operator expected, :>=, 1
    assert_equal expected, sent
  end

  private

  def notify(type, title:, inbox:, idempotency_key: nil, channels: %i[in_app email])
    attributes = {
      notification_type: type,
      recipient: @user,
      title: title,
      channels: channels,
      deliver_later: true,
      idempotency_key: idempotency_key || "inbox-flag-#{SecureRandom.uuid}"
    }
    attributes[:inbox] = inbox unless inbox.nil?
    RecordingStudioNotifications.notify(**attributes)
  end

  def breakdown_counts(result)
    result.data.to_h { |row| [row[:key].to_s, row[:value] || row["value"]] }
  end

  def timeseries_total(result)
    result.data.sum { |row| (row[:value] || row["value"]).to_i }
  end
end
