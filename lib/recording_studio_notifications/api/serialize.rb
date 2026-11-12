# frozen_string_literal: true

module RecordingStudioNotifications
  module Api
    module Serialize
      module_function

      def notification(record)
        {
          id: record.id,
          type: "notification",
          notification_type: record.notification_type,
          title: record.title,
          body: record.body,
          url: record.url,
          inbox: record.inbox,
          read: record.read?,
          archived: record.archived?,
          read_at: record.read_at,
          archived_at: record.archived_at,
          cleared_at: record.cleared_at,
          recording_id: record.recording_id,
          root_recording_id: record.root_recording_id,
          created_at: record.created_at
        }
      end

      def channel_preference(record)
        {
          id: record.id,
          type: "notification_preference",
          notification_type: record.notification_type,
          channel: record.channel,
          enabled: record.enabled,
          cadence: record.cadence
        }
      end
    end
  end
end
