# frozen_string_literal: true

require_relative "api"
require_relative "mcp_copy/descriptions"
require_relative "mcp_copy/outputs"

module RecordingStudioNotifications
  # Registers named MCP tools and types when Recording Studio MCP is loaded.
  # This gem does not depend on it. Hosts that skip MCP keep the UI and API only.
  module McpCopy
    NOTIFICATION_TYPE = "Notification"
    PREFERENCE_TYPE = "NotificationPreference"
    ID_INPUT = { "id" => { description: Descriptions::ID } }.freeze
    LIST_INPUT = {
      "page" => { description: Descriptions::PAGE },
      "per_page" => { description: Descriptions::PER_PAGE }
    }.freeze
    PREFERENCE_WRITE_INPUT = {
      "notification_type" => { description: Descriptions::NOTIFICATION_TYPE_FIELD },
      "channel" => { description: Descriptions::CHANNEL },
      "enabled" => { description: Descriptions::ENABLED },
      "cadence" => { description: Descriptions::CADENCE }
    }.freeze

    TOOLS = [
      {
        name: "list_notifications", type: NOTIFICATION_TYPE, endpoint: Api::INDEX_NAME.to_sym,
        title: Api::Inbox::TITLE, description: Descriptions::LIST, input: LIST_INPUT, output: Outputs::LIST
      },
      {
        name: "show_notification", type: NOTIFICATION_TYPE, endpoint: Api::SHOW_NAME.to_sym,
        title: Api::Show::TITLE, description: Descriptions::SHOW, input: ID_INPUT, output: Outputs::SHOW
      },
      {
        name: "mark_notification_read", type: NOTIFICATION_TYPE, endpoint: Api::MARK_READ_NAME.to_sym,
        title: Api::MarkRead::TITLE, description: Descriptions::MARK_READ, input: ID_INPUT,
        output: Outputs::MARK_READ
      },
      {
        name: "mark_notification_unread", type: NOTIFICATION_TYPE, endpoint: Api::MARK_UNREAD_NAME.to_sym,
        title: Api::MarkUnread::TITLE, description: Descriptions::MARK_UNREAD, input: ID_INPUT,
        output: Outputs::MARK_UNREAD
      },
      {
        name: "archive_notification", type: NOTIFICATION_TYPE, endpoint: Api::ARCHIVE_NAME.to_sym,
        title: Api::Archive::TITLE, description: Descriptions::ARCHIVE, input: ID_INPUT,
        output: Outputs::ARCHIVE
      },
      {
        name: "unarchive_notification", type: NOTIFICATION_TYPE, endpoint: Api::UNARCHIVE_NAME.to_sym,
        title: Api::Unarchive::TITLE, description: Descriptions::UNARCHIVE, input: ID_INPUT,
        output: Outputs::UNARCHIVE
      },
      {
        name: "list_notification_preferences", type: PREFERENCE_TYPE, endpoint: Api::PREFERENCES_NAME.to_sym,
        title: Api::Preferences::TITLE, description: Descriptions::PREFERENCES, input: {},
        output: Outputs::PREFERENCES
      },
      {
        name: "update_notification_preferences", type: PREFERENCE_TYPE,
        endpoint: Api::UPDATE_PREFERENCES_NAME.to_sym,
        title: Api::UpdatePreferences::TITLE, description: Descriptions::UPDATE_PREFERENCES,
        input: PREFERENCE_WRITE_INPUT, output: Outputs::UPDATE_PREFERENCES
      }
    ].freeze

    TYPES = {
      NOTIFICATION_TYPE => Descriptions::NOTIFICATION,
      PREFERENCE_TYPE => Descriptions::NOTIFICATION_PREFERENCE
    }.freeze

    module_function

    def register!
      return unless defined?(::RecordingStudioMcp)

      register_types
      register_tools
    end

    def tool_names
      names = TOOLS.map { |tool| tool.fetch(:name) }
      { public: names, operations: names }
    end

    def register_types
      return unless ::RecordingStudioMcp.respond_to?(:register_type)

      TYPES.each do |type, description|
        ::RecordingStudioMcp.register_type(type: type, description: description)
      end
    end

    def register_tools
      return unless ::RecordingStudioMcp.respond_to?(:register_tool)

      TOOLS.each { |tool| register_endpoint_tool(tool) }
    end

    def register_endpoint_tool(tool)
      ::RecordingStudioMcp.register_tool(
        name: tool.fetch(:name),
        type: tool.fetch(:type),
        endpoint: tool.fetch(:endpoint),
        title: tool.fetch(:title),
        description: tool.fetch(:description),
        input: tool.fetch(:input),
        output: tool.fetch(:output)
      )
    end
    private_class_method :register_types, :register_tools, :register_endpoint_tool
  end
end
