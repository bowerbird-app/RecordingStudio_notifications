# frozen_string_literal: true

module RecordingStudioNotifications
  module McpCopy
    module Descriptions
      NOTIFICATION_FIELDS = Api::ToolDescriptions::NOTIFICATION_FIELDS
      PREFERENCE_FIELDS = Api::ToolDescriptions::PREFERENCE_FIELDS
      CADENCE_LIST = Api::ToolDescriptions::CADENCE_LIST
      NOTIFICATION_SHAPE = Api::ToolDescriptions::NOTIFICATION_SHAPE
      PREFERENCE_SHAPE = Api::ToolDescriptions::PREFERENCE_SHAPE
      HIDDEN = Api::ToolDescriptions::HIDDEN

      NOTIFICATION =
        "A notification is an in-app notice for the signed-in person. It is a stored row, not a page in the tree. " \
        "Inbox notices belong to this workspace or have no workspace. Use list_notifications to page the inbox, " \
        "show_notification to read one item, and mark_notification_read, mark_notification_unread, " \
        "archive_notification, or unarchive_notification to change it. Take id from a list_notifications record."

      NOTIFICATION_PREFERENCE =
        "A notification preference is a saved channel or cadence choice for the signed-in person. " \
        "The rows belong to the person and cover every workspace. Use list_notification_preferences to see " \
        "saved rows. Use update_notification_preferences to change an optional channel, a cadence, or both. " \
        "Copy notification_type from a list_notification_preferences record, or pass a type the app has " \
        "registered that has no row yet. A required channel is always delivered, and a preference cannot " \
        "turn it off."

      LIST =
        "#{NOTIFICATION} List this workspace's inbox, newest first. Notices with no workspace are included. " \
        "Archived notices, notices with the inbox turned off, notices still waiting on a grouped in-app " \
        "delivery, and another person's notices are left out. Pass page and per_page to choose the page. " \
        "Use show_notification when you need one item. Use mark_notification_read, mark_notification_unread, " \
        "or archive_notification to change one. Take id from a record in this list. Returns records and meta. " \
        "Each record has #{NOTIFICATION_FIELDS}. type is the string notification. read is true when read_at or " \
        "cleared_at is set. meta has page, per_page, total_count, and total_pages.".freeze

      SHOW =
        "#{NOTIFICATION} Read one inbox notice for this workspace, or one with no workspace. Use this when " \
        "you have an id from list_notifications and need the full item. #{HIDDEN} Use mark_notification_read, " \
        "mark_notification_unread, or archive_notification to change it. #{NOTIFICATION_SHAPE}".freeze

      MARK_READ = format(
        Api::ToolDescriptions::MARK_READ_FORMAT,
        inbox: "list_notifications",
        show: "show_notification",
        unread: "mark_notification_unread"
      ).freeze
      MARK_UNREAD = format(
        Api::ToolDescriptions::MARK_UNREAD_FORMAT,
        read: "mark_notification_read"
      ).freeze
      ARCHIVE = format(
        Api::ToolDescriptions::ARCHIVE_FORMAT,
        inbox: "list_notifications",
        show: "show_notification",
        read: "mark_notification_read",
        unread: "mark_notification_unread",
        unarchive: "unarchive_notification"
      ).freeze
      UNARCHIVE = format(
        Api::ToolDescriptions::UNARCHIVE_FORMAT,
        archive: "archive_notification",
        inbox: "list_notifications"
      ).freeze

      PREFERENCES =
        "#{NOTIFICATION_PREFERENCE} You need to be signed in for this workspace to call it. " \
        "A type with no saved preference is absent. #{PREFERENCE_SHAPE}".freeze

      UPDATE_PREFERENCES = format(
        Api::ToolDescriptions::UPDATE_PREFERENCES_FORMAT,
        preferences: "list_notification_preferences"
      ).freeze

      PAGE = Api::ToolDescriptions::PAGE
      PER_PAGE = Api::ToolDescriptions::PER_PAGE
      ID = format(
        Api::ToolDescriptions::ID_FORMAT,
        inbox: "list_notifications",
        unarchive: "unarchive_notification"
      )
      NOTIFICATION_TYPE_FIELD = format(
        Api::ToolDescriptions::NOTIFICATION_TYPE_FORMAT,
        preferences: "list_notification_preferences"
      )
      CHANNEL = Api::ToolDescriptions::CHANNEL
      ENABLED = Api::ToolDescriptions::ENABLED
      CADENCE = Api::ToolDescriptions::CADENCE
    end
  end
end
