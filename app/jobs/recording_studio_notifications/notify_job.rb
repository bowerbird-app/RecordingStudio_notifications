# frozen_string_literal: true

module RecordingStudioNotifications
  class NotifyJob < ApplicationJob
    def perform(attributes)
      RecordingStudioNotifications.notify(**attributes.symbolize_keys.merge(deliver_later: false))
    end
  end
end
