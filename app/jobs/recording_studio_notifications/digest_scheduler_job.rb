# frozen_string_literal: true

module RecordingStudioNotifications
  class DigestSchedulerJob < ApplicationJob
    def perform(at: Time.current)
      NotificationDigest.due(at).find_each do |digest|
        ActiveSupport::Notifications.instrument(
          "digest_due.recording_studio_notifications",
          digest_id: digest.id,
          recipient: digest.recipient,
          notification_type: digest.notification_type,
          cadence: digest.cadence
        )
      end
    end
  end
end