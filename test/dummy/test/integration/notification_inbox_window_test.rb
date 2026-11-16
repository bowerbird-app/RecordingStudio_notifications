# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationInboxWindowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @rollup_delivery_enabled = RecordingStudioNotifications.configuration.rollup_delivery_enabled
    @viewer = User.create!(
      email: "inbox-window-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @other = User.create!(
      email: "inbox-window-other-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    Current.actor = @other
    @hidden_root = root_for("9 window hidden #{SecureRandom.hex(4)}", @other)
    Current.actor = nil
    sign_in @viewer
  end

  teardown do
    RecordingStudioNotifications.configuration.rollup_delivery_enabled = @rollup_delivery_enabled
    Current.actor = nil
  end

  test "menu and index stay capped as notices grow and skip an inaccessible root" do
    add_notices(30)
    hidden = add_hidden("Hidden from the window")

    small_menu = nil
    small_index = nil
    menu_sql = nil
    loaded_menu = instantiated_notifications do
      menu_sql = notification_selects { get_menu(limit: 5) }
      small_menu = @menu
    end
    loaded_index = instantiated_notifications { small_index = get_index }

    assert_operator loaded_menu, :<=, 5
    assert_operator loaded_index, :<=, RecordingStudioNotifications::NotificationsController::PER_PAGE
    assert_equal 30, small_menu.fetch("unread_count")
    assert_equal [ "Notice 0", "Notice 1", "Notice 2", "Notice 3", "Notice 4" ],
                 small_menu.fetch("notifications").map { |item| item.fetch("title") }
    refute_includes response.body, hidden.title
    assert_includes small_index, "Notice 0"
    refute_includes small_index, hidden.title
    assert_operator small_index.index("Notice 0"), :<, small_index.index("Notice 1")

    add_notices(15, start: 30)
    loaded_menu_again = instantiated_notifications { get_menu(limit: 5) }
    loaded_index_again = instantiated_notifications { get_index }

    assert_equal loaded_menu, loaded_menu_again
    assert_equal loaded_index, loaded_index_again
    assert_equal 45, @menu.fetch("unread_count")
    assert_equal "Notice 0", @menu.fetch("notifications").first.fetch("title")
    refute_includes @menu.fetch("notifications").map { |item| item.fetch("title") }, hidden.title

    get_index(page: 2)

    assert_includes response.body, "Notice 44"
    refute_includes response.body, "Notice 0"
    refute_includes response.body, hidden.title

    RecordingStudioNotifications.configuration.rollup_delivery_enabled = false
    limited_sql = notification_selects { get_menu(limit: 5) }

    assert limited_sql.any? { |statement| statement.match?(/LIMIT/i) }, limited_sql.inspect
    assert menu_sql.any? { |statement| statement.match?(/LIMIT/i) }, menu_sql.inspect
    assert_equal 5, @menu.fetch("notifications").size
    assert_equal 45, @menu.fetch("unread_count")
  end

  test "fallback check still fills the menu when the newest row is inaccessible" do
    add_notices(8)
    hidden = add_hidden("Hidden before the ruby check")

    without_sql_root_ids { get_menu(limit: 5) }

    titles = @menu.fetch("notifications").map { |item| item.fetch("title") }

    assert_equal [ "Notice 0", "Notice 1", "Notice 2", "Notice 3", "Notice 4" ], titles
    refute_includes titles, hidden.title
    assert_equal 8, @menu.fetch("unread_count")
  end

  test "a shown rollup keeps every notice in the group and the group page stays capped" do
    RecordingStudioNotifications.notification_types.register(
      :window_daily,
      label: "Window daily",
      scope: :global,
      default_channels: [ :in_app ],
      available_channels: [ :in_app ],
      allowed_cadences: [ :daily ],
      default_cadence: :daily
    )
    RecordingStudioNotifications.configuration.rollup_delivery_enabled = true
    daily = 4.times.map { |index| add_daily("Daily #{index}", index) }
    add_notices(12, start: 0, created_at: 2.days.ago)
    group = RecordingStudioNotifications::Services::InboxGrouping.new(
      recipient: @viewer,
      notifications: daily
    ).call.first.groups.first

    loaded = instantiated_notifications { get_menu(limit: 1) }
    item = @menu.fetch("notifications").fetch(0)

    assert_operator loaded, :<=, daily.size
    assert_equal true, item.fetch("rollup")
    assert_equal daily.map(&:title).sort, item.fetch("children").map { |child| child.fetch("title") }.sort
    refute_includes response.body, "Notice 0"
    assert_equal 16, @menu.fetch("unread_count")

    loaded_page = instantiated_notifications do
      get "/notifications/notifications/groups/#{group.id}/page", params: { inbox_scope: "all" }
    end

    assert_response :success
    assert_operator loaded_page, :<=, RecordingStudioNotifications::NotificationsController::GROUP_NOTIFICATIONS_PER_PAGE
    assert_includes response.body, "Daily 0"
    assert_includes response.body, "Daily 3"
  end

  test "a long rollup group page does not instantiate the whole group" do
    RecordingStudioNotifications.notification_types.register(
      :window_daily_page,
      label: "Window daily page",
      scope: :global,
      default_channels: [ :in_app ],
      available_channels: [ :in_app ],
      allowed_cadences: [ :daily ],
      default_cadence: :daily
    )
    RecordingStudioNotifications.configuration.rollup_delivery_enabled = true
    notifications = 30.times.map { |index| add_daily("Paged daily #{index}", index, type: :window_daily_page) }
    group = RecordingStudioNotifications::Services::InboxGrouping.new(
      recipient: @viewer,
      notifications: notifications
    ).call.first.groups.first

    loaded = instantiated_notifications do
      get "/notifications/notifications/groups/#{group.id}/page", params: { page: 2, inbox_scope: "all" }
    end

    assert_response :success
    assert_operator loaded, :<=, 20
    assert_includes response.body, "Paged daily 20"
    assert_includes response.body, "Paged daily 29"
    refute_includes response.body, "Paged daily 0"
    refute_includes response.body, "Paged daily 19"
  end

  private

  def add_notices(count, start: 0, created_at: Time.current)
    count.times.map do |offset|
      index = start + offset
      RecordingStudioNotifications::Notification.create!(
        recipient: @viewer,
        notification_type: :system_announcement,
        title: "Notice #{index}",
        created_at: created_at - index.minutes,
        updated_at: created_at - index.minutes
      )
    end
  end

  def add_daily(title, index, type: :window_daily)
    RecordingStudioNotifications::Notification.create!(
      recipient: @viewer,
      notification_type: type,
      title: title,
      created_at: Time.current - index.minutes,
      updated_at: Time.current - index.minutes
    )
  end

  def add_hidden(title)
    RecordingStudioNotifications::Notification.create!(
      recipient: @viewer,
      notification_type: :page_comment,
      title: title,
      root_recording: @hidden_root,
      created_at: 1.hour.from_now,
      updated_at: 1.hour.from_now
    )
  end

  def get_menu(limit:)
    get "/notifications/notifications/menu.json", params: { inbox_scope: "all", limit: limit }
    assert_response :success
    @menu = JSON.parse(response.body)
  end

  def get_index(page: 1)
    get "/notifications", params: { inbox_scope: "all", page: page }
    assert_response :success
    response.body
  end

  def instantiated_notifications
    count = 0
    callback = lambda do |*args|
      payload = args.last
      next unless payload[:class_name] == "RecordingStudioNotifications::Notification"

      count += payload[:record_count].to_i
    end
    ActiveSupport::Notifications.subscribed(callback, "instantiation.active_record") { yield }
    count
  end

  def notification_selects
    statements = []
    callback = lambda do |*args|
      payload = args.last
      statement = payload[:sql].to_s
      next unless statement.include?("recording_studio_notifications_notifications")
      next unless statement.lstrip.match?(/\ASELECT/i)

      statements << statement
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end

  def without_sql_root_ids
    RecordingStudioAccessible.define_singleton_method(:authorized_root_recording_ids_supported?) { false }
    yield
  ensure
    RecordingStudioAccessible.singleton_class.remove_method(:authorized_root_recording_ids_supported?)
  end

  def root_for(name, owner)
    workspace = Workspace.create!(name: name)
    root = RecordingStudio.create_root_recording!(workspace, actor: owner)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: root, actor: owner)
    raise result.error if result.failure?

    root
  end
end
