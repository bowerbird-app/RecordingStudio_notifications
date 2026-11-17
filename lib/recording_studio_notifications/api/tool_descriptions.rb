# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    module ToolDescriptions
      PAGE_SIZE = 25
      NOTIFICATION_FIELDS = "id, type, notification_type, title, body, url, inbox, read, " \
                            "archived, read_at, archived_at, cleared_at, recording_id, " \
                            "root_recording_id, and created_at"
      PREFERENCE_FIELDS = "id, type, notification_type, channel, enabled, and cadence"
      CADENCES = NotificationTypeRegistry::CADENCES.map(&:to_s).freeze
      CADENCE_LIST = "#{CADENCES[0..-2].join(', ')}, and #{CADENCES.last}".freeze
      NOTIFICATION_SHAPE = "Returns #{NOTIFICATION_FIELDS}. type is the string notification. " \
                           "read is true when read_at or cleared_at is set.".freeze
      PREFERENCE_SHAPE = "Returns records. Each record has #{PREFERENCE_FIELDS}. " \
                         "type is the string notification_preference. A channel row has channel and enabled, " \
                         "and cadence is empty. A cadence row has cadence, and channel and enabled are empty.".freeze
      HIDDEN = "A missing id, an archived notification, a notification with the inbox turned off, " \
               "another person's notification, or a notification in another workspace returns not found. " \
               "A notification this person is not allowed to see returns forbidden."

      INBOX = "List the signed-in person's notifications for this workspace, newest first. " \
              "Notifications with no workspace are included. Archived notifications are left out. " \
              "A notification sent with the inbox turned off is left out. A notice still waiting on a " \
              "grouped in-app delivery is left out. Another person's notifications are left out. " \
              "Pass page and per_page to choose the page. Use notifications.show when you need one item. " \
              "Use notifications.mark_read, notifications.mark_unread, or notifications.archive to change one. " \
              "Take id from a record in this list. Returns records and meta. Each record has " \
              "#{NOTIFICATION_FIELDS}. type is the string notification. read is true when read_at or " \
              "cleared_at is set. meta has page, per_page, total_count, and total_pages.".freeze

      SHOW = "Read one notification for the signed-in person in this workspace, or one with no workspace. " \
             "Use this when you have an id from notifications.inbox and need the full item. #{HIDDEN} " \
             "Use notifications.mark_read, notifications.mark_unread, or notifications.archive to change it. " \
             "#{NOTIFICATION_SHAPE}".freeze

      MARK_READ = "Mark one notification read for the signed-in person. Use this when a notifications.inbox " \
                  "or notifications.show result has read set to false. Calling it again keeps the first read_at. " \
                  "#{HIDDEN} Use notifications.mark_unread to undo it. #{NOTIFICATION_SHAPE}".freeze

      MARK_UNREAD = "Mark one notification unread for the signed-in person. Use this to undo " \
                    "notifications.mark_read. read becomes false, and read_at and cleared_at are cleared. " \
                    "Calling it on an already unread notification leaves it unread. #{HIDDEN} " \
                    "#{NOTIFICATION_SHAPE}".freeze

      ARCHIVE = "Archive one notification for the signed-in person so it leaves the inbox. Use this when " \
                "the person is done with an item from notifications.inbox. archived becomes true and " \
                "archived_at is set. A second archive of that id returns not found. After this, " \
                "notifications.inbox, notifications.show, notifications.mark_read, and " \
                "notifications.mark_unread also return not found for that id. Use notifications.unarchive " \
                "with the same id to put it back. A notification with the inbox turned off, a missing id, " \
                "another person's notification, or a notification in another workspace returns not found. " \
                "A notification this person is not allowed to see returns forbidden. #{NOTIFICATION_SHAPE}".freeze

      UNARCHIVE = "Put an archived notification back in the inbox for the signed-in person. Use this after " \
                  "notifications.archive, with the same id. That id is not in notifications.inbox while the " \
                  "notification is archived. archived becomes false and archived_at is cleared. A notification " \
                  "that was not archived stays that way. A notification with the inbox turned off, a missing id, " \
                  "another person's notification, or a notification in another workspace returns not found. " \
                  "A notification this person is not allowed to see returns forbidden. #{NOTIFICATION_SHAPE}".freeze

      PREFERENCES = "List the notification preferences saved for the signed-in person. You need access to " \
                    "this workspace to call it. The rows belong to the person and cover every workspace. " \
                    "Use notifications.update_preferences to change a row. Copy notification_type " \
                    "from a record when you update. A type with no saved preference is absent. A required " \
                    "channel is always delivered, and a preference cannot turn it off. #{PREFERENCE_SHAPE}".freeze

      UPDATE_PREFERENCES = "Change one optional channel, one cadence, or both, for the signed-in person. " \
                           "Call notifications.preferences first. Copy notification_type from a " \
                           "notifications.preferences record, " \
                           "or pass a type the app has registered that has no row yet. Send channel with enabled " \
                           "to turn an optional channel on or off. The bundled channel is in_app. Any other " \
                           "channel must be one the app has registered and one this type offers as optional. " \
                           "A required channel is always delivered, and a write for it is rejected. Leave " \
                           "channel out to leave channel choices unchanged. Sending enabled without channel " \
                           "changes nothing. Send cadence to set how often this type is delivered. Allowed " \
                           "cadence values are #{CADENCE_LIST}. The type may allow some of these and reject " \
                           "the rest. Passing the type's default cadence removes the saved cadence row. Leave " \
                           "cadence out to leave the cadence unchanged. An unknown notification_type, an unknown " \
                           "channel, or a cadence the type does not allow is rejected. If you send a channel and " \
                           "a cadence and the cadence is rejected, the channel change is already saved. " \
                           "#{PREFERENCE_SHAPE}".freeze

      PAGE = "Which page to return. The first page is 1. Leave it out, or pass 0 or a negative number, " \
             "to get page 1."
      PER_PAGE = "How many notifications to return on the page. Leave it out for #{PAGE_SIZE}. " \
                 "A value of 0 or less also uses #{PAGE_SIZE}. A value above #{PAGE_SIZE} is cut down " \
                 "to #{PAGE_SIZE}.".freeze
      ID = "Copy this from the id of a notifications.inbox record. notifications.unarchive can also use " \
           "the id you archived earlier, because that row is no longer in the inbox."
      NOTIFICATION_TYPE = "The notification type to change. Copy notification_type from a " \
                          "notifications.preferences record. You can also pass a type the app has registered " \
                          "that has no saved row yet."
      CHANNEL = "Optional channel to turn on or off. Send it with enabled. The bundled value is in_app. " \
                "Any other value must be a channel the app has registered and an optional channel for this " \
                "notification type. A required channel is rejected because it is always delivered. Leave it " \
                "out to leave channel choices unchanged."
      ENABLED = "true turns the channel on. false turns it off. Send this with channel. Leave it out when " \
                "you are not changing a channel. Sending it without channel changes nothing."
      CADENCE = "How often this notification type is delivered. Allowed values are #{CADENCE_LIST}. " \
                "The type may allow some of these and reject the rest. Passing the type's default removes " \
                "the saved cadence row. Leave it out to leave the cadence unchanged.".freeze
    end
  end
end
