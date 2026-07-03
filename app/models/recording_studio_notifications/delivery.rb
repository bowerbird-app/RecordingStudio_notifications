# frozen_string_literal: true

module RecordingStudioNotifications
  class Delivery < ApplicationRecord
    self.table_name = "recording_studio_notifications_deliveries"

    STATUSES = %w[pending delivered failed].freeze

    belongs_to :notification, class_name: "RecordingStudioNotifications::Notification"

    validates :channel, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate :registered_channel

    scope :pending, -> { where(status: "pending") }
    scope :delivered, -> { where(status: "delivered") }
    scope :failed, -> { where(status: "failed") }
    scope :for_channel, ->(channel) { where(channel: channel.to_s) }

    def pending?
      status == "pending"
    end

    def delivered?
      status == "delivered"
    end

    def failed?
      status == "failed"
    end

    def mark_delivered!(at: Time.current)
      update!(status: "delivered", delivered_at: delivered_at || at, error_message: nil)
    end

    def mark_failed!(error)
      update!(status: "failed", error_message: error.to_s)
    end

    private

    def registered_channel
      return if channel.blank?
      return if RecordingStudioNotifications.channels.registered?(channel.to_sym)

      errors.add(:channel, "is not registered")
    end
  end
end
