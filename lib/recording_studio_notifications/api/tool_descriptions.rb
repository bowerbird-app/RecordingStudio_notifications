# frozen_string_literal: true

require_relative "tool_description_formats"

module RecordingStudioNotifications
  module Api
    module ToolDescriptions
      INBOX = (
        "List the signed-in person's notifications for this workspace, newest first. " \
        "Notifications with no workspace are included. Archived notifications are left out. " \
        "A notification sent with the inbox turned off is left out. A notice still waiting on a " \
        "grouped in-app delivery is left out. Another person's notifications are left out. " +
        format(
          INBOX_TAIL_FORMAT,
          show: "notifications.show",
          read: "notifications.mark_read",
          unread: "notifications.mark_unread",
          archive: "notifications.archive"
        )
      ).freeze

      SHOW = format(
        SHOW_FORMAT,
        inbox: "notifications.inbox",
        read: "notifications.mark_read",
        unread: "notifications.mark_unread",
        archive: "notifications.archive"
      ).freeze

      MARK_READ = format(
        MARK_READ_FORMAT,
        inbox: "notifications.inbox",
        show: "notifications.show",
        unread: "notifications.mark_unread"
      ).freeze
      MARK_UNREAD = format(MARK_UNREAD_FORMAT, read: "notifications.mark_read").freeze
      ARCHIVE = format(
        ARCHIVE_FORMAT,
        inbox: "notifications.inbox",
        show: "notifications.show",
        read: "notifications.mark_read",
        unread: "notifications.mark_unread",
        unarchive: "notifications.unarchive"
      ).freeze
      UNARCHIVE = format(
        UNARCHIVE_FORMAT,
        archive: "notifications.archive",
        inbox: "notifications.inbox"
      ).freeze

      PREFERENCES = "List the notification preferences saved for the signed-in person. You need access to " \
                    "this workspace to call it. The rows belong to the person and cover every workspace. " \
                    "Use notifications.update_preferences to change a row. Copy notification_type " \
                    "from a record when you update. A type with no saved preference is absent. A required " \
                    "channel is always delivered, and a preference cannot turn it off. #{PREFERENCE_SHAPE}".freeze

      UPDATE_PREFERENCES = format(UPDATE_PREFERENCES_FORMAT, preferences: "notifications.preferences").freeze

      PAGE = "Which page to return. The first page is 1. Leave it out, or pass 0 or a negative number, " \
             "to get page 1."
      PER_PAGE = "How many notifications to return on the page. Leave it out for #{PAGE_SIZE}. " \
                 "A value of 0 or less also uses #{PAGE_SIZE}. A value above #{PAGE_SIZE} is cut down " \
                 "to #{PAGE_SIZE}.".freeze
      ID = format(ID_FORMAT, inbox: "notifications.inbox", unarchive: "notifications.unarchive")
      NOTIFICATION_TYPE = format(NOTIFICATION_TYPE_FORMAT, preferences: "notifications.preferences")
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
