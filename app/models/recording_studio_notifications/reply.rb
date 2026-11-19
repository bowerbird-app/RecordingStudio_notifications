# frozen_string_literal: true

module RecordingStudioNotifications
  class Reply < ApplicationRecord
    self.table_name = "recording_studio_notifications_replies"

    STATUSES = %w[pending ok rejected].freeze

    belongs_to :notification, class_name: "RecordingStudioNotifications::Notification"

    validates :channel, :idempotency_key, :status, presence: true
    validates :status, inclusion: { in: STATUSES }
  end
end
