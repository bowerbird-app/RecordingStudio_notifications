# frozen_string_literal: true

require "test_helper"

class McpCopyTest < Minitest::Test
  BANNED = [
    "Accessible",
    "Access",
    ":edit",
    ":view",
    "permission",
    "role",
    "Admin"
  ].freeze

  EXPECTED_TOOLS = {
    "list_notifications" => :"notifications.inbox",
    "show_notification" => :"notifications.show",
    "mark_notification_read" => :"notifications.mark_read",
    "mark_notification_unread" => :"notifications.mark_unread",
    "archive_notification" => :"notifications.archive",
    "unarchive_notification" => :"notifications.unarchive",
    "list_notification_preferences" => :"notifications.preferences",
    "update_notification_preferences" => :"notifications.update_preferences"
  }.freeze

  WRITE_TOOLS = %w[
    mark_notification_read
    mark_notification_unread
    archive_notification
    unarchive_notification
    update_notification_preferences
  ].freeze

  def test_tool_names_are_the_eight_notification_endpoints
    names = tool_names_on_surfaces

    assert_equal EXPECTED_TOOLS.keys, names.fetch(:public)
    assert_equal EXPECTED_TOOLS.keys, names.fetch(:operations)
    assert_equal names.fetch(:public), names.fetch(:operations)
  end

  def test_named_tools_map_to_existing_api_endpoints
    endpoints = RecordingStudioNotifications::Api::ENDPOINTS.map { |endpoint| endpoint.fetch(:name).to_sym }
    mapped = RecordingStudioNotifications::McpCopy::TOOLS.to_h do |tool|
      [tool.fetch(:name), tool.fetch(:endpoint)]
    end

    assert_equal EXPECTED_TOOLS, mapped
    mapped.each_value do |endpoint|
      assert_includes endpoints, endpoint
    end
  end

  def test_types_use_short_public_names
    types = RecordingStudioNotifications::McpCopy::TYPES

    assert_equal %w[Notification NotificationPreference], types.keys
    assert_equal RecordingStudioNotifications::McpCopy::NOTIFICATION_TYPE, "Notification"
    assert_equal RecordingStudioNotifications::McpCopy::PREFERENCE_TYPE, "NotificationPreference"
    assert_includes types.fetch("Notification"), "in-app notice"
    assert_includes types.fetch("NotificationPreference"), "channel or cadence"
    types.each_value { |description| refute_banned(description, "type") }
  end

  def test_each_tool_has_copy_for_humans_and_agents
    RecordingStudioNotifications::McpCopy::TOOLS.each do |tool|
      name = tool.fetch(:name)
      description = tool.fetch(:description)
      type = tool.fetch(:type)

      assert tool.fetch(:title).present?, name
      assert_operator description.split.size, :>=, 40, name
      assert tool.fetch(:output).present?, name
      refute_banned(description, name)
      refute_match(/\bnotifications\./, description, name)
      assert_includes %w[Notification NotificationPreference], type
      next unless WRITE_TOOLS.include?(name)

      assert_match(
        /list_notifications|list_notification_preferences|mark_notification_read|archive_notification/,
        description,
        name
      )
    end
  end

  def test_shared_tool_bodies_interpolate_mcp_names
    api = RecordingStudioNotifications::Api::ToolDescriptions
    mcp = RecordingStudioNotifications::McpCopy::Descriptions

    assert_equal api::NOTIFICATION_SHAPE, mcp::NOTIFICATION_SHAPE
    assert_equal api::PREFERENCE_SHAPE, mcp::PREFERENCE_SHAPE
    assert_equal api::HIDDEN, mcp::HIDDEN
    show_body = format(
      api::SHOW_FORMAT,
      inbox: "list_notifications",
      read: "mark_notification_read",
      unread: "mark_notification_unread",
      archive: "archive_notification"
    )
    assert_equal "#{mcp::NOTIFICATION} #{show_body}", mcp::SHOW
    assert_includes mcp::LIST, format(
      api::INBOX_TAIL_FORMAT,
      show: "show_notification",
      read: "mark_notification_read",
      unread: "mark_notification_unread",
      archive: "archive_notification"
    )
    assert_equal format(
      api::MARK_READ_FORMAT,
      inbox: "list_notifications",
      show: "show_notification",
      unread: "mark_notification_unread"
    ), mcp::MARK_READ
    assert_equal format(api::MARK_UNREAD_FORMAT, read: "mark_notification_read"), mcp::MARK_UNREAD
    assert_equal format(
      api::ARCHIVE_FORMAT,
      inbox: "list_notifications",
      show: "show_notification",
      read: "mark_notification_read",
      unread: "mark_notification_unread",
      unarchive: "unarchive_notification"
    ), mcp::ARCHIVE
    assert_equal format(
      api::UNARCHIVE_FORMAT,
      archive: "archive_notification",
      inbox: "list_notifications"
    ), mcp::UNARCHIVE
    assert_equal format(api::UPDATE_PREFERENCES_FORMAT, preferences: "list_notification_preferences"),
                 mcp::UPDATE_PREFERENCES
    assert_equal format(api::ID_FORMAT, inbox: "list_notifications", unarchive: "unarchive_notification"),
                 mcp::ID
    assert_equal format(api::NOTIFICATION_TYPE_FORMAT, preferences: "list_notification_preferences"),
                 mcp::NOTIFICATION_TYPE_FIELD
  end

  def test_member_tools_use_the_notification_type
    notification_tools = RecordingStudioNotifications::McpCopy::TOOLS.select do |tool|
      tool.fetch(:type) == "Notification"
    end
    preference_tools = RecordingStudioNotifications::McpCopy::TOOLS.select do |tool|
      tool.fetch(:type) == "NotificationPreference"
    end

    assert_equal(
      %w[
        list_notifications
        show_notification
        mark_notification_read
        mark_notification_unread
        archive_notification
        unarchive_notification
      ],
      notification_tools.map { |tool| tool.fetch(:name) }
    )
    assert_equal(
      %w[list_notification_preferences update_notification_preferences],
      preference_tools.map { |tool| tool.fetch(:name) }
    )
  end

  def test_register_is_a_noop_when_mcp_is_not_loaded
    refute defined?(::RecordingStudioMcp)
    assert_nil RecordingStudioNotifications::McpCopy.register!
  end

  def test_gemspec_does_not_depend_on_recording_studio_mcp
    gemspec = File.read(File.expand_path("../recording_studio_notifications.gemspec", __dir__))
    entry = File.read(File.expand_path("../lib/recording_studio_notifications.rb", __dir__))
    engine = File.read(File.expand_path("../lib/recording_studio_notifications/engine.rb", __dir__))

    refute_includes gemspec, "recording_studio_mcp"
    refute_includes entry, "require \"recording_studio_mcp\""
    assert_includes entry, "require \"recording_studio_notifications/mcp_copy\""
    assert_includes engine,
                    "initializer \"recording_studio_notifications.mcp\", after: \"recording_studio_notifications.api\""
    assert_includes engine, "RecordingStudioNotifications::McpCopy.register!"
    refute File.exist?(File.expand_path("../lib/recording_studio_notifications/mcp.rb", __dir__))
  end

  private

  def tool_names_on_surfaces
    names = RecordingStudioNotifications::McpCopy.tool_names
    { public: names.fetch(:public), operations: names.fetch(:operations) }
  end

  def refute_banned(text, label)
    BANNED.each do |word|
      refute_match(/\b#{Regexp.escape(word)}\b/, text, "#{label} includes #{word}")
    end
  end
end
