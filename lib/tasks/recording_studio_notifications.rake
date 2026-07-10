# frozen_string_literal: true

namespace :recording_studio_notifications do
  desc "Deliver due notification digests (set FORCE=1 in development to process all pending digests)"
  task deliver_due_digests: :environment do
    abort "recording_studio_notifications:deliver_due_digests is available only in development" unless Rails.env.development?

    at = if ENV["FORCE"] == "1"
           RecordingStudioNotifications::NotificationDigest.pending.maximum(:period_ends_at) || Time.current
         elsif ENV["DIGEST_AT"].present?
           Time.zone.parse(ENV.fetch("DIGEST_AT"))
         else
           Time.current
         end

    pending_before = RecordingStudioNotifications::NotificationDigest.pending.where("period_ends_at <= ?", at).count
    RecordingStudioNotifications::DigestSchedulerJob.perform_now(at: at)

    puts "Processed #{pending_before} due notification digest#{'s' unless pending_before == 1}."
  end
end