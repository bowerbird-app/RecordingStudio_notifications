# frozen_string_literal: true

require "test_helper"

class AllNotificationsScreenTest < ActiveSupport::TestCase
  setup do
    @recipient = User.create!(
      email: "admin-screen-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @actor = User.create!(
      email: "admin-screen-actor-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    RecordingStudioNotifications.notification_types.register(
      :admin_screen_global,
      label: "Admin screen global",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    RecordingStudioNotifications.notification_types.register(
      :admin_screen_root,
      label: "Admin screen root",
      scope: :root,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    @title = "Admin screen #{SecureRandom.hex(4)}"
    @global = RecordingStudioNotifications.notify(
      notification_type: :admin_screen_global,
      recipient: @recipient,
      title: @title,
      deliver_later: false,
      idempotency_key: "admin-screen-global-#{SecureRandom.uuid}"
    )
    Current.actor = @actor
    root = RecordingStudio.root_recording_for(Workspace.create!(name: "Admin screen #{SecureRandom.hex(4)}"))
    @rooted = RecordingStudioNotifications.notify(
      notification_type: :admin_screen_root,
      recipient: @recipient,
      actor: @actor,
      root_recording: root,
      title: "Rooted #{SecureRandom.hex(4)}",
      deliver_later: false,
      idempotency_key: "admin-screen-root-#{SecureRandom.uuid}"
    )
    @rooted.mark_read!
  ensure
    Current.actor = nil
  end

  test "query filters and column labels describe root and global rows" do
    screen = RecordingStudioNotifications::Admin::AllNotificationsScreen
    relation = screen.query.call(nil)
    search = screen.table.filters.find { |filter| filter.key == :search }

    matches = search.options[:apply].call(relation, @title, nil)
    assert_includes matches, @global
    assert_equal relation, search.options[:apply].call(relation, " ", nil)

    columns = screen.table.columns.index_by(&:key)
    assert_equal "Global", columns.fetch(:scope).value.call(@global, nil)
    assert_equal "Root", columns.fetch(:scope).value.call(@rooted, nil)
    assert_equal "User ##{@recipient.id}", columns.fetch(:recipient).value.call(@global, nil)
    assert_equal "-", columns.fetch(:actor).value.call(@global, nil)
    assert_equal "User", columns.fetch(:actor).value.call(@rooted, nil)
    assert_equal "Unread", columns.fetch(:status).value.call(@global, nil)
    assert_equal "Read", columns.fetch(:status).value.call(@rooted, nil)
  end
end
