# frozen_string_literal: true

module RecordingStudioNotifications
  class NotificationDigest < ApplicationRecord
    self.table_name = "recording_studio_notifications_digests"

    STATUSES = %w[pending delivered cancelled].freeze

    belongs_to :recipient, polymorphic: true
    belongs_to :root_recording, class_name: "RecordingStudio::Recording", optional: true
    has_many :items,
         class_name: "RecordingStudioNotifications::NotificationDigestItem",
         foreign_key: :digest_id,
         dependent: :destroy
    has_many :source_notifications, through: :items, source: :notification

    validates :recipient, :notification_type, :cadence, :status, :period_starts_at, :period_ends_at, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate :registered_notification_type
    validate :allowed_cadence
    validate :period_ends_after_start

    scope :pending, -> { where(status: "pending") }
    scope :delivered, -> { where(status: "delivered") }
    scope :due, ->(at = Time.current) { pending.where("period_ends_at <= ?", at) }

    def pending?
      status == "pending"
    end

    def delivered?
      status == "delivered"
    end

    def cancelled?
      status == "cancelled"
    end

    private

    def type_definition
      @type_definition ||= RecordingStudioNotifications.notification_types[notification_type]
    end

    def registered_notification_type
      return if notification_type.blank?
      return if type_definition

      errors.add(:notification_type, "is not registered")
    end

    def allowed_cadence
      return if cadence.blank? || !type_definition
      return if type_definition.allowed_cadences.include?(cadence.to_sym)

      errors.add(:cadence, "is not allowed for this notification type")
    end

    def period_ends_after_start
      return if period_starts_at.blank? || period_ends_at.blank?
      return if period_ends_at > period_starts_at

      errors.add(:period_ends_at, "must be after the digest period start")
    end
  end
end
