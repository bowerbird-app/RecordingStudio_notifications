# frozen_string_literal: true

require "test_helper"

class NotifyServiceHooksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @recipient = User.create!(
      email: "notify-hooks-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :notify_service_hook,
      label: "Notify service hook",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    RecordingStudioNotifications.notification_types.register(
      :notify_service_hook_quiet,
      label: "Notify service hook quiet",
      scope: :global,
      default_channels: [],
      required_channels: [],
      available_channels: [:in_app]
    )
    clear_enqueued_jobs
  end

  teardown do
    %i[before_service around_service after_service].each do |hook|
      RecordingStudio.configuration.hooks.clear(hook)
    end
  end

  test "notify runs service hooks on the core registry around create" do
    seen = []
    hooks = RecordingStudio.configuration.hooks
    hooks.before_service do |service_class, payload|
      seen << [:before, service_class, payload.fetch(:notification_type), payload.fetch(:recipient), payload.fetch(:channels)]
    end
    hooks.around_service do |service, block|
      seen << [:around, service.class]
      result = block.call
      seen << [:around_done, result]
      result
    end
    hooks.after_service do |service_class, notification|
      seen << [:after, service_class, notification]
    end
    events = []
    callback = lambda { |*args|
      events << args.last.fetch(:notification_type)
      seen << :event
    }
    performed_before = performed_jobs.size

    notification = nil
    ActiveSupport::Notifications.subscribed(callback, "notify.recording_studio_notifications") do
      assert_enqueued_with(job: RecordingStudioNotifications::DeliveryJob) do
        notification = RecordingStudioNotifications.notify(
          notification_type: :notify_service_hook,
          recipient: @recipient,
          title: "Hooked notice",
          idempotency_key: "notify-hooks-#{SecureRandom.uuid}",
          deliver_later: true
        )
      end
    end

    assert_equal [
      [:before, RecordingStudioNotifications::Services::Notify, "notify_service_hook", @recipient, [:in_app]],
      [:around, RecordingStudioNotifications::Services::Notify],
      :event,
      [:around_done, notification],
      [:after, RecordingStudioNotifications::Services::Notify, notification]
    ], seen
    assert_equal ["notify_service_hook"], events
    assert_instance_of RecordingStudioNotifications::Notification, notification
    assert_equal performed_before, performed_jobs.size
  end

  test "notify does not run service hooks when it returns nil" do
    called = false
    hooks = RecordingStudio.configuration.hooks
    hooks.before_service { called = true }
    hooks.around_service do |_service, block|
      called = true
      block.call
    end
    hooks.after_service { called = true }

    result = nil
    assert_no_enqueued_jobs only: RecordingStudioNotifications::DeliveryJob do
      result = RecordingStudioNotifications.notify(
        notification_type: :notify_service_hook_quiet,
        recipient: @recipient,
        title: "No channels",
        idempotency_key: "notify-hooks-quiet-#{SecureRandom.uuid}",
        deliver_later: true
      )
    end

    assert_nil result
    refute called
  end
end
