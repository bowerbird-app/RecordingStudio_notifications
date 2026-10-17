# frozen_string_literal: true

require "test_helper"

class NotificationStateTest < ActiveSupport::TestCase
  setup do
    @recipient = User.create!(
      email: "notification-state-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :notification_state_global,
      label: "Notification state global",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    RecordingStudioNotifications.notification_types.register(
      :notification_state_root,
      label: "Notification state root",
      scope: :root,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    RecordingStudioNotifications.notification_types.register(
      :notification_state_optional,
      label: "Notification state optional",
      scope: :optional_root,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
  end

  test "read archive and scope helpers keep the first timestamp" do
    notification = RecordingStudioNotifications.notify(
      notification_type: :notification_state_global,
      recipient: @recipient,
      title: "State helpers",
      deliver_later: false,
      idempotency_key: "notification-state-#{SecureRandom.uuid}"
    )
    read_at = Time.utc(2026, 10, 17, 12, 0, 0)
    archived_at = Time.utc(2026, 10, 17, 13, 0, 0)

    assert notification.global?
    assert notification.rootless?
    refute notification.archived?

    notification.mark_read!(at: read_at)
    notification.mark_read!(at: read_at + 1.hour)
    assert_equal read_at, notification.reload.read_at

    notification.mark_unread!
    assert notification.reload.unread?
    assert_nil notification.read_at
    assert_nil notification.cleared_at

    notification.archive!(at: archived_at)
    notification.archive!(at: archived_at + 1.hour)
    assert notification.reload.archived?
    assert_equal archived_at, notification.archived_at

    notification.unarchive!
    refute notification.reload.archived?
  end

  test "root scope requires a root and global scope rejects one" do
    missing_root = RecordingStudioNotifications::Notification.new(
      notification_type: "notification_state_root",
      recipient: @recipient,
      title: "Needs a root"
    )
    refute missing_root.valid?
    assert_includes missing_root.errors[:root_recording], "is required"

    Current.actor = @recipient
    root = RecordingStudio.root_recording_for(Workspace.create!(name: "State root #{SecureRandom.hex(4)}"))
    global_with_root = RecordingStudioNotifications::Notification.new(
      notification_type: "notification_state_global",
      recipient: @recipient,
      title: "Global stays rootless",
      root_recording: root
    )
    refute global_with_root.valid?
    assert_includes global_with_root.errors[:root_recording], "must be blank for global notifications"
  ensure
    Current.actor = nil
  end

  test "optional root rejects a recording from a different root" do
    Current.actor = @recipient
    first_root = RecordingStudio.root_recording_for(Workspace.create!(name: "State A #{SecureRandom.hex(4)}"))
    second_root = RecordingStudio.root_recording_for(Workspace.create!(name: "State B #{SecureRandom.hex(4)}"))
    mismatched = RecordingStudioNotifications::Notification.new(
      notification_type: "notification_state_optional",
      recipient: @recipient,
      title: "Mismatched roots",
      root_recording: first_root,
      recording: second_root
    )

    refute mismatched.valid?
    assert_includes mismatched.errors[:root_recording], "must match recording and notifiable root"
  ensure
    Current.actor = nil
  end
end
