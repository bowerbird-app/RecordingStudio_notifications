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
      HIDDEN =
        "A missing id, an archived notification, a notification with the inbox turned off, " \
        "another person's notification, or a notification in another workspace returns not found. " \
        "A notification this person is not allowed to see returns forbidden."
      ARCHIVE_NOT_FOUND =
        "A notification with the inbox turned off, a missing id, " \
        "another person's notification, or a notification in another workspace returns not found. " \
        "A notification this person is not allowed to see returns forbidden."
      SHOW_FORMAT =
        "Read one notification for the signed-in person in this workspace, or one with no workspace. " \
        "Use this when you have an id from %<inbox>s and need the full item. #{HIDDEN} " \
        "Use %<read>s, %<unread>s, or %<archive>s to change it. " \
        "#{NOTIFICATION_SHAPE}".freeze
      INBOX_TAIL_FORMAT =
        "Pass page and per_page to choose the page. Use %<show>s when you need one item. " \
        "Use %<read>s, %<unread>s, or %<archive>s to change one. " \
        "Take id from a record in this list. Returns records and meta. Each record has " \
        "#{NOTIFICATION_FIELDS}. type is the string notification. read is true when read_at or " \
        "cleared_at is set. meta has page, per_page, total_count, and total_pages.".freeze

      MARK_READ_FORMAT =
        "Mark one notification read for the signed-in person. Use this when a %<inbox>s " \
        "or %<show>s result has read set to false. Calling it again keeps the first read_at. " \
        "#{HIDDEN} Use %<unread>s to undo it. #{NOTIFICATION_SHAPE}".freeze
      MARK_UNREAD_FORMAT =
        "Mark one notification unread for the signed-in person. Use this to undo " \
        "%<read>s. read becomes false, and read_at and cleared_at are cleared. " \
        "Calling it on an already unread notification leaves it unread. #{HIDDEN} " \
        "#{NOTIFICATION_SHAPE}".freeze
      ARCHIVE_FORMAT =
        "Archive one notification for the signed-in person so it leaves the inbox. Use this when " \
        "the person is done with an item from %<inbox>s. archived becomes true and " \
        "archived_at is set. A second archive of that id returns not found. After this, " \
        "%<inbox>s, %<show>s, %<read>s, and " \
        "%<unread>s also return not found for that id. Use %<unarchive>s " \
        "with the same id to put it back. #{ARCHIVE_NOT_FOUND} #{NOTIFICATION_SHAPE}".freeze
      UNARCHIVE_FORMAT =
        "Put an archived notification back in the inbox for the signed-in person. Use this after " \
        "%<archive>s, with the same id. That id is not in %<inbox>s while the " \
        "notification is archived. archived becomes false and archived_at is cleared. A notification " \
        "that was not archived stays that way. #{ARCHIVE_NOT_FOUND} #{NOTIFICATION_SHAPE}".freeze
      UPDATE_PREFERENCES_FORMAT =
        "Change one optional channel, one cadence, or both, for the signed-in person. " \
        "Call %<preferences>s first. Copy notification_type from a " \
        "%<preferences>s record, " \
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
      ID_FORMAT =
        "Copy this from the id of a %<inbox>s record. %<unarchive>s can also use " \
        "the id you archived earlier, because that row is no longer in the inbox."
      NOTIFICATION_TYPE_FORMAT =
        "The notification type to change. Copy notification_type from a " \
        "%<preferences>s record. You can also pass a type the app has registered " \
        "that has no saved row yet."
    end
  end
end
