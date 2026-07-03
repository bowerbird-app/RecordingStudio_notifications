# frozen_string_literal: true

module RecordingStudioNotifications
  class Notification < ApplicationRecord
    self.table_name = "recording_studio_notifications_notifications"

    belongs_to :recipient, polymorphic: true
    belongs_to :actor, polymorphic: true, optional: true
    belongs_to :notifiable, polymorphic: true, optional: true
    belongs_to :recording, class_name: "RecordingStudio::Recording", optional: true
    belongs_to :root_recording, class_name: "RecordingStudio::Recording", optional: true
    has_many :deliveries, class_name: "RecordingStudioNotifications::Delivery", dependent: :destroy

    validates :notification_type, :title, :recipient, presence: true
    validates :url, length: { maximum: 2048 }, allow_blank: true
    validate :registered_notification_type
    validate :safe_url

    scope :newest_first, -> { order(created_at: :desc, id: :desc) }
    scope :unread, -> { where(read_at: nil) }
    scope :read, -> { where.not(read_at: nil) }
    scope :archived, -> { where.not(archived_at: nil) }
    scope :active, -> { where(archived_at: nil) }
    scope :for_recipient, ->(recipient) { where(recipient: recipient) }
    scope :for_root_recording, ->(recording) { where(root_recording: recording) }
    scope :of_type, ->(type) { where(notification_type: type.to_s) }

    def notification_type_key
      notification_type.to_s.to_sym
    end

    def read?
      read_at.present?
    end

    def unread?
      !read?
    end

    def archived?
      archived_at.present?
    end

    def mark_read!(at: Time.current)
      update!(read_at: read_at || at)
    end

    def mark_unread!
      update!(read_at: nil)
    end

    def archive!(at: Time.current)
      update!(archived_at: archived_at || at)
    end

    private

    def registered_notification_type
      return if notification_type.blank?
      return if RecordingStudioNotifications.notification_types.registered?(notification_type_key)

      errors.add(:notification_type, "is not registered")
    end

    def safe_url
      return if RecordingStudioNotifications::UrlSafety.safe?(url)

      errors.add(:url, "is not safe")
    end
  end
end
