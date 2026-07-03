# frozen_string_literal: true

module RecordingStudioNotifications
  class ApplicationJob < ActiveJob::Base
    queue_as { RecordingStudioNotifications.configuration.queue_name }
  end
end
