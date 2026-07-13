# frozen_string_literal: true

namespace :recording_studio_notifications do
  desc "Deliver closed notification rollups"
  task deliver_rollups: :environment do
    RecordingStudioNotifications::RollupDeliveryJob.perform_now
  end
end