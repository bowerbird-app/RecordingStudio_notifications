# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NotificationMenuRowStyleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @owner = User.create!(
      email: "menu-style-owner-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @viewer = User.create!(
      email: "menu-style-viewer-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    Current.actor = @owner
    @root = root_for("Menu style #{SecureRandom.hex(4)}")
    @other_root = root_for("Menu style other #{SecureRandom.hex(4)}")
    @denied_root = root_for("Menu style denied #{SecureRandom.hex(4)}")
    bootstrap_owner!(@root, @owner)
    bootstrap_owner!(@other_root, @owner)
    bootstrap_owner!(@denied_root, @owner)
    grant!(@root, @viewer, :view)
    grant!(@other_root, @viewer, :view)

    RecordingStudioNotifications.notification_types.register(
      :menu_row_hidden,
      label: "Menu row hidden",
      scope: :global,
      inbox: false,
      default_channels: %i[in_app email],
      available_channels: %i[in_app email],
      allowed_cadences: [ :individual ],
      default_cadence: :individual
    )

    @unread_title = "Unread mention #{SecureRandom.hex(4)}"
    @read_title = "Read approval #{SecureRandom.hex(4)}"
    @rollup_child_title = "Unread comment #{SecureRandom.hex(4)}"
    @other_root_title = "Other root mention #{SecureRandom.hex(4)}"
    @denied_title = "Denied root mention #{SecureRandom.hex(4)}"
    @hidden_title = "Hidden from menu #{SecureRandom.hex(4)}"

    notify_mention(@other_root, @other_root_title, read: true)
    notify_mention(@denied_root, @denied_title, read: false)
    notify_hidden
    notify_comment(@rollup_child_title, read: false)
    notify_comment("Read comment #{SecureRandom.hex(4)}", read: true)
    RecordingStudioNotifications::RollupDeliveryJob.perform_now(now: Time.utc(2099, 1, 1))
    notify_approval
    notify_mention(@root, @unread_title, read: false)

    Current.actor = nil
    sign_in @viewer
    switch_to_root!(@root)
  end

  teardown do
    Current.actor = nil
  end

  test "menu emphasizes allowed unread rows, mutes read rows, and hides denied rows" do
    payload = menu_payload
    titles = notification_titles(payload)

    assert_includes titles, @unread_title
    assert_includes titles, @read_title
    assert_includes titles, "Page comment"
    refute_includes titles, @other_root_title
    refute_includes titles, @denied_title
    refute_includes titles, @hidden_title
    assert_equal 2, payload.fetch("unread_count")
    assert_menu_contract(payload)

    html = payload.fetch("menu_html")
    refute_includes html, @other_root_title
    refute_includes html, @denied_title
    refute_includes html, @hidden_title
    assert_row_styles(html)

    all_scope = menu_payload(inbox_scope: "all")
    all_titles = notification_titles(all_scope)

    assert_includes all_titles, @other_root_title
    refute_includes all_titles, @denied_title
    refute_includes all_titles, @hidden_title
    assert_equal 2, all_scope.fetch("unread_count")
    refute_includes all_scope.fetch("menu_html"), @denied_title
    refute_includes all_scope.fetch("menu_html"), @hidden_title
  end

  private

  def menu_payload(inbox_scope: nil)
    params = inbox_scope ? { inbox_scope: inbox_scope, limit: 25 } : { limit: 25 }
    get "/notifications/notifications/menu.json", params: params
    assert_response :success
    JSON.parse(response.body)
  end

  def notification_titles(payload)
    payload.fetch("notifications").flat_map do |item|
      [ item["title"], *Array(item["children"]).map { |child| child["title"] } ]
    end
  end

  def assert_menu_contract(payload)
    assert_equal %w[menu_html notifications polling_interval_seconds unread_count], payload.keys.sort

    unread_item = payload.fetch("notifications").find { |item| item["title"] == @unread_title }
    read_item = payload.fetch("notifications").find { |item| item["title"] == @read_title }
    rollup_item = payload.fetch("notifications").find { |item| item["title"] == "Page comment" }

    assert_equal %w[body href icon time title unread], unread_item.keys.sort
    assert_equal true, unread_item.fetch("unread")
    assert_equal %w[body href icon time title unread], read_item.keys.sort
    assert_equal false, read_item.fetch("unread")
    assert_equal %w[body children href icon rollup time title unread], rollup_item.keys.sort
    assert_equal true, rollup_item.fetch("rollup")
    assert_equal true, rollup_item.fetch("unread")
    assert_equal 2, rollup_item.fetch("children").size
    assert_includes payload.fetch("menu_html"), "See all notifications"
  end

  def assert_row_styles(html)
    document = Nokogiri::HTML(html)
    style = document.at_css("style").text
    unread_row = row_for(document, @unread_title)
    read_row = row_for(document, @read_title)
    rollup_row = row_for(document, "Page comment")

    assert_includes style, "gap: 0;"
    assert_includes style, "background-color: transparent;"
    assert_includes style, "background-color: var(--surface-border-color);"
    assert_includes style, "font-weight: 400;"
    assert_includes style, "color: var(--surface-muted-content-color);"
    assert_includes style, "li:has(.fp-red-dot) .truncate"
    assert_includes style, "li:has(.fp-rollup-counter-badge) .truncate"
    assert_includes style, "font-weight: 600;"
    assert_includes style, "color: var(--surface-content-color);"
    assert_includes html, "rsn-notification-menu"

    assert unread_row.at_css(".fp-red-dot")
    assert_nil read_row.at_css(".fp-red-dot")
    assert_nil read_row.at_css(".fp-rollup-counter-badge")
    assert rollup_row.at_css(".fp-rollup-counter-badge")
    assert_nil rollup_row.at_css(".fp-red-dot")
  end

  def row_for(document, title)
    document.css("li").find do |item|
      item.css(".truncate").any? { |node| node.text == title }
    end
  end

  def notify_mention(root, title, read:)
    notification = RecordingStudioNotifications.notify(
      notification_type: :mention,
      recipient: @viewer,
      actor: @owner,
      root_recording: root,
      title: title,
      body: "Someone said your name.",
      idempotency_key: "menu-style-mention-#{SecureRandom.uuid}"
    )
    notification.mark_read! if read
    notification
  end

  def notify_approval
    notification = RecordingStudioNotifications.notify(
      notification_type: :approval_requested,
      recipient: @viewer,
      actor: @owner,
      root_recording: @root,
      title: @read_title,
      body: "A page is waiting for a yes.",
      idempotency_key: "menu-style-approval-#{SecureRandom.uuid}"
    )
    notification.mark_read!
  end

  def notify_comment(title, read:)
    notification = RecordingStudioNotifications.notify(
      notification_type: :page_comment,
      recipient: @viewer,
      actor: @owner,
      root_recording: @root,
      title: title,
      body: "A comment landed on the page.",
      idempotency_key: "menu-style-comment-#{SecureRandom.uuid}"
    )
    notification.mark_read! if read
    notification
  end

  def notify_hidden
    RecordingStudioNotifications.notify(
      notification_type: :menu_row_hidden,
      recipient: @viewer,
      title: @hidden_title,
      body: "This stays out of the menu.",
      inbox: false,
      channels: %i[in_app email],
      idempotency_key: "menu-style-hidden-#{SecureRandom.uuid}"
    )
  end

  def root_for(name)
    RecordingStudio.root_recording_for(Workspace.create!(name: name))
  end

  def bootstrap_owner!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
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
      manager_actor: @owner
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end

  def switch_to_root!(root)
    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: root.id,
        return_to: "/notifications"
      }
    }
  end
end
