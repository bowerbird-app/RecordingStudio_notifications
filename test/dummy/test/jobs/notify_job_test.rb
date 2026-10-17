# frozen_string_literal: true

require "test_helper"

class NotifyJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @recipient = User.create!(
      email: "notify-job-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :notify_job_test,
      label: "Notify job test",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
  end

  test "perform notifies inline and does not enqueue delivery" do
    assert_no_enqueued_jobs do
      RecordingStudioNotifications::NotifyJob.perform_now(
        "notification_type" => "notify_job_test",
        "recipient" => @recipient,
        "title" => "From the job",
        "idempotency_key" => "notify-job-#{SecureRandom.uuid}"
      )
    end

    notification = RecordingStudioNotifications::Notification.find_by!(title: "From the job", recipient: @recipient)
    assert notification.deliveries.sole.delivered?
  end
end
