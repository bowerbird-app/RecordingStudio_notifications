# frozen_string_literal: true

require "recording_studio_notifications/services/digest_delivery"

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
        ) { Services::DigestDelivery.call(digest: digest, at: at) }
      end
    end
  end
end