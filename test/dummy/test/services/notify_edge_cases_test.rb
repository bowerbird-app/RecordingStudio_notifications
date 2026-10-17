# frozen_string_literal: true

require "test_helper"

class NotifyEdgeCasesTest < ActiveSupport::TestCase
  setup do
    @recipient = User.create!(
      email: "notify-edges-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @other = User.create!(
      email: "notify-edges-other-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    define_access_actions
    RecordingStudioNotifications.notification_types.register(
      :notify_edge_plain,
      label: "Notify edge plain",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
  end

  test "notify_each delivers to each recipient" do
    results = RecordingStudioNotifications.notify_each(
      recipients: [@recipient, @other],
      notification_type: :notify_edge_plain,
      title: "Each recipient",
      deliver_later: false
    )

    assert_equal [@recipient.id, @other.id], results.map { |notification| notification.recipient_id }
    assert results.all? { |notification| notification.deliveries.sole.delivered? }
  end

  test "a required channel the adapter refuses is rejected" do
    adapter = Object.new
    adapter.define_singleton_method(:deliver) { |notification:, delivery:| }
    adapter.define_singleton_method(:available_for?) { |recipient:, notification:, delivery:| false }
    RecordingStudioNotifications.channels.register(:notify_edge_closed, adapter)
    RecordingStudioNotifications.notification_types.register(
      :notify_edge_closed,
      label: "Notify edge closed",
      scope: :global,
      default_channels: [],
      required_channels: [:notify_edge_closed],
      available_channels: [:notify_edge_closed]
    )

    error = assert_raises(ArgumentError) do
      RecordingStudioNotifications.notify(
        notification_type: :notify_edge_closed,
        recipient: @recipient,
        title: "Closed channel",
        deliver_later: false
      )
    end

    assert_includes error.message, "required channel is not available for recipient: notify_edge_closed"
  end

  test "a required channel outside the type's available list is rejected" do
    adapter = Object.new
    adapter.define_singleton_method(:deliver) { |notification:, delivery:| }
    RecordingStudioNotifications.channels.register(:notify_edge_ghost, adapter)
    type = RecordingStudioNotifications.notification_types.register(
      :notify_edge_unavailable,
      label: "Notify edge unavailable",
      scope: :global,
      default_channels: [:in_app],
      required_channels: [:in_app],
      available_channels: [:in_app]
    )
    type.required_channels << :notify_edge_ghost

    error = assert_raises(ArgumentError) do
      RecordingStudioNotifications.notify(
        notification_type: :notify_edge_unavailable,
        recipient: @recipient,
        title: "Unavailable channel",
        deliver_later: false
      )
    end

    assert_includes error.message, "channel is not available for notify_edge_unavailable: notify_edge_ghost"
  end

  test "creation_action denies and allows through Accessible" do
    RecordingStudioNotifications.notification_types.register(
      :notify_edge_denied,
      label: "Notify edge denied",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app],
      creation_action: :coverage_deny_notify
    )
    RecordingStudioNotifications.notification_types.register(
      :notify_edge_allowed,
      label: "Notify edge allowed",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app],
      creation_action: :coverage_allow_notify
    )
    Current.actor = @recipient

    error = assert_raises(RecordingStudioNotifications::Services::NotificationAuthorization::NotAuthorized) do
      RecordingStudioNotifications.notify(
        notification_type: :notify_edge_denied,
        recipient: @recipient,
        title: "Denied create",
        deliver_later: false
      )
    end
    assert_includes error.message, "not authorized to create notify_edge_denied"

    notification = RecordingStudioNotifications.notify(
      notification_type: :notify_edge_allowed,
      recipient: @recipient,
      title: "Allowed create",
      deliver_later: false,
      idempotency_key: "notify-edge-allowed-#{SecureRandom.uuid}"
    )
    assert_equal @recipient, notification.recipient
  ensure
    Current.actor = nil
  end

  test "a unique constraint replay returns the notification created first" do
    existing = RecordingStudioNotifications.notify(
      notification_type: :notify_edge_plain,
      recipient: @recipient,
      title: "Already stored",
      deliver_later: false,
      idempotency_key: "notify-edge-replay-#{SecureRandom.uuid}"
    )
    finds = 0

    with_singleton_method(RecordingStudioNotifications::Notification, :find_by, lambda { |*_args, **_kwargs|
      finds += 1
      finds == 1 ? nil : existing
    }) do
      with_singleton_method(RecordingStudioNotifications::Notification, :create!, lambda { |*_args, **_kwargs|
        raise ActiveRecord::RecordNotUnique, "duplicate key"
      }) do
        replay = RecordingStudioNotifications.notify(
          notification_type: :notify_edge_plain,
          recipient: @recipient,
          title: "Replay",
          deliver_later: false,
          idempotency_key: "notify-edge-replay-new-#{SecureRandom.uuid}"
        )

        assert_equal existing, replay
      end
    end

    assert_operator finds, :>=, 2
  end

  private

  def define_access_actions
    return if RecordingStudioAccessible.action_defined?(:coverage_deny_notify)

    RecordingStudioAccessible.define_action(:coverage_deny_notify) { |**| false }
    RecordingStudioAccessible.define_action(:coverage_allow_notify) { |**| true }
  end

  def with_singleton_method(object, method_name, implementation)
    original = object.method(method_name)
    object.define_singleton_method(method_name) do |*args, **kwargs, &block|
      implementation.call(*args, **kwargs, &block)
    end
    yield
  ensure
    object.singleton_class.send(:remove_method, method_name)
    object.define_singleton_method(method_name, original)
  end
end
