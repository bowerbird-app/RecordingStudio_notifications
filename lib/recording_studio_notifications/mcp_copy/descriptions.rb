# frozen_string_literal: true

module RecordingStudioNotifications
  module McpCopy
    module Descriptions
      NOTIFICATION_FIELDS = Api::ToolDescriptions::NOTIFICATION_FIELDS
      PREFERENCE_FIELDS = Api::ToolDescriptions::PREFERENCE_FIELDS
      CADENCE_LIST = Api::ToolDescriptions::CADENCE_LIST
      NOTIFICATION_SHAPE = "Returns #{NOTIFICATION_FIELDS}. type is the string notification. " \
                           "read is true when read_at or cleared_at is set.".freeze
      PREFERENCE_SHAPE = "Returns records. Each record has #{PREFERENCE_FIELDS}. " \
                         "type is the string notification_preference. A channel row has channel and enabled, " \
                         "and cadence is empty. A cadence row has cadence, and channel and enabled are empty.".freeze
      HIDDEN = "A missing id, an archived notification, a notification with the inbox turned off, " \
               "another person's notification, or a notification in another workspace returns not found. " \
               "A notification this person cannot see returns forbidden."

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

      MARK_READ =
        "Mark one notification read for the signed-in person. Call list_notifications or show_notification " \
        "first. Use an id whose read is false. Calling it again keeps the first read_at. #{HIDDEN} " \
        "Use mark_notification_unread to undo it. #{NOTIFICATION_SHAPE}".freeze

      MARK_UNREAD =
        "Mark one notification unread for the signed-in person. Call list_notifications or show_notification " \
        "first, then use mark_notification_unread to undo mark_notification_read. read becomes false, and " \
        "read_at and cleared_at are cleared. Calling it on an already unread notification leaves it unread. " \
        "#{HIDDEN} #{NOTIFICATION_SHAPE}".freeze

      ARCHIVE =
        "Archive one notification for the signed-in person so it leaves the inbox. Call list_notifications " \
        "or show_notification first. Use this when the person is done with that item. archived becomes true " \
        "and archived_at is set. A second archive of that id returns not found. After this, " \
        "list_notifications, show_notification, mark_notification_read, and mark_notification_unread also " \
        "return not found for that id. Use unarchive_notification with the same id to put it back. " \
        "A notification with the inbox turned off, a missing id, another person's notification, or a " \
        "notification in another workspace returns not found. A notification this person cannot see " \
        "returns forbidden. #{NOTIFICATION_SHAPE}".freeze

      UNARCHIVE =
        "Put an archived notification back in the inbox for the signed-in person. Use this after " \
        "archive_notification, with the same id. That id is not in list_notifications while the " \
        "notification is archived. archived becomes false and archived_at is cleared. A notification " \
        "that was not archived stays that way. A notification with the inbox turned off, a missing id, " \
        "another person's notification, or a notification in another workspace returns not found. " \
        "A notification this person cannot see returns forbidden. #{NOTIFICATION_SHAPE}".freeze

      PREFERENCES =
        "#{NOTIFICATION_PREFERENCE} You need to be signed in for this workspace to call it. " \
        "A type with no saved preference is absent. #{PREFERENCE_SHAPE}".freeze

      UPDATE_PREFERENCES =
        "Change one optional channel, one cadence, or both, for the signed-in person. Call " \
        "list_notification_preferences first. Copy notification_type from a list_notification_preferences " \
        "record, or pass a type the app has registered that has no row yet. Send channel with enabled to " \
        "turn an optional channel on or off. The bundled channel is in_app. Any other channel must be one " \
        "the app has registered and one this type offers as optional. A required channel is always " \
        "delivered, and a write for it is rejected. Leave channel out to leave channel choices unchanged. " \
        "Sending enabled without channel changes nothing. Send cadence to set how often this type is " \
        "delivered. Allowed cadence values are #{CADENCE_LIST}. The type may allow some of these and " \
        "reject the rest. Passing the type's default cadence removes the saved cadence row. Leave cadence " \
        "out to leave the cadence unchanged. An unknown notification_type, an unknown channel, or a " \
        "cadence the type does not allow is rejected. If you send a channel and a cadence and the cadence " \
        "is rejected, the channel change is already saved. #{PREFERENCE_SHAPE}".freeze

      PAGE = Api::ToolDescriptions::PAGE
      PER_PAGE = Api::ToolDescriptions::PER_PAGE
      ID = "Copy this from the id of a list_notifications record. unarchive_notification can also use " \
           "the id you archived earlier, because that row is no longer in the inbox."
      NOTIFICATION_TYPE_FIELD =
        "The notification type to change. Copy notification_type from a list_notification_preferences " \
        "record. You can also pass a type the app has registered that has no saved row yet."
      CHANNEL = Api::ToolDescriptions::CHANNEL
      ENABLED = Api::ToolDescriptions::ENABLED
      CADENCE = Api::ToolDescriptions::CADENCE
    end
  end
end
