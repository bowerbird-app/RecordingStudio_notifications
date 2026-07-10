# frozen_string_literal: true

module RecordingStudioNotifications
  class NotificationDigestItem < ApplicationRecord
    self.table_name = "recording_studio_notifications_digest_items"

    belongs_to :digest, class_name: "RecordingStudioNotifications::NotificationDigest"
    belongs_to :notification, class_name: "RecordingStudioNotifications::Notification"

    validates :notification_id, uniqueness: true
    validate :notification_matches_digest

    private

    def notification_matches_digest
      return if digest.blank? || notification.blank?

      if notification.recipient != digest.recipient
        errors.add(:notification, "must belong to the digest recipient")
      end

      if notification.notification_type != digest.notification_type
        errors.add(:notification, "must match the digest notification type")
      end

      return if notification.root_recording_id == digest.root_recording_id

      errors.add(:notification, "must match the digest root recording")
    end
  end
end
