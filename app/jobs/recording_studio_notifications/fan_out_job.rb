# frozen_string_literal: true

module RecordingStudioNotifications
  class FanOutJob < ApplicationJob
    def perform(attributes)
      Services::FanOut.perform(attributes)
    end
  end
end
