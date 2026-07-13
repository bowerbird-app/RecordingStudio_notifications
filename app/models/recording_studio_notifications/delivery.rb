# frozen_string_literal: true

module RecordingStudioNotifications
  class Delivery < ApplicationRecord
    self.table_name = "recording_studio_notifications_deliveries"

    STATUSES = %w[pending processing delivered failed].freeze
    GENERIC_FAILURE_MESSAGE = "Delivery failed"

    belongs_to :notification, class_name: "RecordingStudioNotifications::Notification"

    validates :channel, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate :registered_channel

    scope :pending, -> { where(status: "pending") }
    scope :delivered, -> { where(status: "delivered") }
    scope :failed, -> { where(status: "failed") }
    scope :processing, -> { where(status: "processing") }
    scope :for_channel, ->(channel) { where(channel: channel.to_s) }
    scope :rollups, -> { where("metadata ->> 'rollup' = ?", "true") }
    scope :retryable_rollups, -> { rollups.where(status: %w[pending failed]) }

    def pending?
      status == "pending"
    end

    def delivered?
      status == "delivered"
    end

    def failed?
      status == "failed"
    end

    def processing?
      status == "processing"
    end

    def rollup?
      metadata["rollup"] == true
    end

    def deferred_rollup?
      pending? && rollup?
    end

    def reserve_rollup!(at: Time.current)
      update!(status: "processing", rollup_reserved_at: at, error_message: nil)
    end

    def mark_delivered!(at: Time.current)
      update!(status: "delivered", delivered_at: delivered_at || at, rollup_reserved_at: nil, error_message: nil)
    end

    def mark_failed!(error = nil)
      message = error.respond_to?(:message) ? error.message.to_s : error.to_s
      update!(
        status: "failed",
        rollup_reserved_at: nil,
        error_message: message.presence&.truncate(1_000) || GENERIC_FAILURE_MESSAGE
      )
    end

    private

    def registered_channel
      return if channel.blank?
      return if RecordingStudioNotifications.channels.registered?(channel.to_sym)

      errors.add(:channel, "is not registered")
    end
  end
end
