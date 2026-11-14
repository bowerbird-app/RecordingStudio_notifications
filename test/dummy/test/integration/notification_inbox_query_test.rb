# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationInboxQueryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @viewer = User.create!(
      email: "inbox-query-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @other = User.create!(
      email: "inbox-query-other-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    Current.actor = @viewer
    @allowed_root = root_for("0 inbox query #{SecureRandom.hex(4)}", @viewer)
    @trashed_root = root_for("8 inbox query trashed #{SecureRandom.hex(4)}", @viewer)
    @trashed_root.update_columns(trashed_at: Time.current)
    Current.actor = @other
    @hidden_root = root_for("9 inbox query hidden #{SecureRandom.hex(4)}", @other)
    Current.actor = nil

    @allowed = add_root_notification("Allowed root", @allowed_root)
    @trashed = add_root_notification("Trashed root", @trashed_root)
    @hidden = add_root_notification("Hidden root", @hidden_root)
    @read = add_announcement("Already read", read: true)
    @announcements = 4.times.map { |index| add_announcement("Visible #{index}") }
    @other_users = add_announcement("Someone else", recipient: @other)
    sign_in @viewer
  end

  teardown do
    Current.actor = nil
  end

  test "inbox query count stays flat as notifications grow" do
    assert RecordingStudioNotifications::Services::InboxScope.authorized_root_recording_ids_supported?

    get_menu
    small_menu_queries = capture_queries { get_menu }
    small_list_queries = capture_queries { list_page }
    small_unread = @menu.fetch("unread_count")
    small_total = @list.fetch(:meta).fetch(:total_count)

    12.times { |index| add_announcement("Visible extra #{index}") }

    large_menu_queries = capture_queries { get_menu }
    large_list_queries = capture_queries { list_page }

    assert_equal query_names(small_menu_queries), query_names(large_menu_queries)
    assert_equal query_names(small_list_queries), query_names(large_list_queries)
    assert_equal small_unread + 12, @menu.fetch("unread_count")
    assert_equal small_total + 12, @list.fetch(:meta).fetch(:total_count)
    assert_equal 10, @list.fetch(:rows).size
    assert_equal 1, @list.fetch(:meta).fetch(:page)
    assert_operator @list.fetch(:meta).fetch(:total_pages), :>, 1

    visible_ids = inbox_relation.pluck(:id)
    assert_includes visible_ids, @allowed.id
    assert_includes visible_ids, @read.id
    refute_includes visible_ids, @hidden.id
    refute_includes visible_ids, @trashed.id
    refute_includes visible_ids, @other_users.id

    updates = notification_updates do
      patch "/notifications/notifications/clear_all", params: { inbox_scope: "all" }
    end
    assert_equal 1, updates.size

    (@announcements + [@allowed]).each do |notification|
      notification.reload
      assert notification.cleared_at.present?
      assert_nil notification.read_at
      assert_in_delta notification.cleared_at, notification.updated_at, 1
    end
    assert @read.reload.cleared_at.nil?
    assert @read.read_at.present?
    assert @hidden.reload.unread?
    assert @trashed.reload.unread?
    assert @other_users.reload.unread?
    assert_equal [@hidden.id, @trashed.id].sort,
                 RecordingStudioNotifications::Notification.for_recipient(@viewer).unread.pluck(:id).sort
  end

  test "a pending in-app rollup stays out of the inbox and a normal in-app row stays in" do
    rolled = add_announcement("Waiting on the digest")
    rolled.deliveries.create!(channel: "in_app", status: "pending", metadata: { "rollup" => true })
    immediate = add_announcement("Ready now")
    immediate.deliveries.create!(channel: "in_app", status: "pending", metadata: {})

    ids = inbox_relation.pluck(:id)

    refute_includes ids, rolled.id
    assert_includes ids, immediate.id
    assert_includes ids, @allowed.id
    refute_includes ids, @hidden.id
    refute_includes ids, @trashed.id
  end

  test "older Accessible still hides a root the viewer cannot see" do
    sql_queries = capture_queries { get_menu(limit: 25) }
    fallback_queries = without_sql_root_ids { capture_queries { get_menu(limit: 25) } }

    assert_operator fallback_queries.size, :>, sql_queries.size
    assert_includes response.body, "Allowed root"
    refute_includes response.body, "Hidden root"
    refute_includes response.body, "Trashed root"
    assert_includes response.body, @announcements.first.title
  end

  test "partial inbox and unread indexes exist" do
    indexes = RecordingStudioNotifications::Notification.connection.indexes(
      RecordingStudioNotifications::Notification.table_name
    )
    inbox = indexes.find { |index| index.name == "idx_dummy_rsn_notifications_inbox" }
    unread = indexes.find { |index| index.name == "idx_dummy_rsn_notifications_unread" }

    assert inbox
    assert unread
    assert_equal %w[recipient_type recipient_id created_at id], inbox.columns
    assert_equal %w[recipient_type recipient_id], unread.columns
    assert_match(/archived_at IS NULL/i, inbox.where)
    assert_match(/inbox/i, inbox.where)
    assert_match(/read_at IS NULL/i, unread.where)
    assert_match(/cleared_at IS NULL/i, unread.where)
    assert_match(/inbox/i, unread.where)
  end

  private

  def without_sql_root_ids
    RecordingStudioAccessible.define_singleton_method(:authorized_root_recording_ids_supported?) { false }
    yield
  ensure
    RecordingStudioAccessible.singleton_class.remove_method(:authorized_root_recording_ids_supported?)
  end

  def get_menu(limit: 5)
    get "/notifications/notifications/menu.json", params: { inbox_scope: "all", limit: limit }
    assert_response :success
    @menu = JSON.parse(response.body)
  end

  def list_page
    relation = inbox_relation
    @list = RecordingStudioNotifications::Api::Query.paginate(relation, page: 1, per_page: 10)
  end

  def inbox_relation
    RecordingStudioNotifications::Services::InboxScope.relation(
      recipient: @viewer,
      actor: @viewer,
      inbox_scope: "all"
    )
  end

  def add_announcement(title, recipient: @viewer, read: false)
    RecordingStudioNotifications::Notification.create!(
      recipient: recipient,
      notification_type: :system_announcement,
      title: title,
      read_at: (Time.current if read)
    )
  end

  def add_root_notification(title, root)
    RecordingStudioNotifications::Notification.create!(
      recipient: @viewer,
      notification_type: :page_comment,
      title: title,
      root_recording: root
    )
  end

  def root_for(name, owner)
    workspace = Workspace.create!(name: name)
    root = RecordingStudio.root_recording_for(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: root, actor: owner)
    raise result.error if result.failure?

    root
  end

  def capture_queries(&)
    ActiveRecord::Base.connection.clear_query_cache
    queries = []
    callback = lambda do |_name, _started, _finished, _id, payload|
      next if payload[:cached]
      next if payload[:name].to_s.include?("SCHEMA")
      sql = payload[:sql].to_s
      next if sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      queries << payload[:name].to_s
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
    queries
  end

  def query_names(queries)
    queries.tally.map { |name, count| "#{name} x#{count}" }.sort
  end

  def notification_updates(&)
    updates = []
    callback = lambda do |_name, _started, _finished, _id, payload|
      sql = payload[:sql].to_s
      updates << sql if sql.match?(/UPDATE\s+"recording_studio_notifications_notifications"/i)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
    updates
  end
end
