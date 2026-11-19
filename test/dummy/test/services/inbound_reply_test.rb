# frozen_string_literal: true

require "test_helper"

class InboundReplyTest < ActiveSupport::TestCase
  setup do
    @recipient = create_user("reply-recipient")
    @other = create_user("reply-other")
    RecordingStudioNotifications.notification_types.register(
      :inbound_reply_notice,
      label: "Inbound reply notice",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    @calls = []
    register_handler { RecordingStudioNotifications::ReplyResult.ok }
  end

  teardown do
    RecordingStudioNotifications.reply_handlers.clear!
    Current.actor = nil
  end

  test "thread_key is stored and a retry keeps the first value" do
    notification = notify(thread_key: " thread-7 ")
    assert_equal "thread-7", notification.reload.thread_key

    again = notify(thread_key: "thread-8", idempotency_key: notification.idempotency_key)
    assert_equal notification.id, again.id
    assert_equal "thread-7", again.reload.thread_key

    without_key = notify(idempotency_key: "reply-no-thread")
    assert_nil without_key.thread_key
  end

  test "fan out stores thread_key" do
    RecordingStudioNotifications.register_recipient_scope(:inbound_reply_users) { User.where(id: @recipient.id) }
    job = RecordingStudioNotifications.notify_fan_out(
      recipient_scope: :inbound_reply_users,
      notification_type: :inbound_reply_notice,
      actor: @recipient,
      title: "Fan out reply",
      idempotency_key: "reply-fan-#{SecureRandom.hex(4)}",
      thread_key: " fan-thread "
    )

    assert_equal "fan-thread", job.arguments.first.fetch("thread_key")
    job.perform_now

    stored = RecordingStudioNotifications::Notification.find_by!(idempotency_key: job.arguments.first.fetch("idempotency_key"))
    assert_equal "fan-thread", stored.thread_key
    assert_equal @recipient, stored.recipient
  end

  test "reply_target resolves a delivery to the notification and recipient" do
    notification = notify
    delivery = notification.deliveries.sole
    target = RecordingStudioNotifications.reply_target(delivery_id: delivery.id)

    assert_equal notification, target.notification
    assert_equal @recipient, target.recipient
    assert_nil RecordingStudioNotifications.reply_target(delivery_id: SecureRandom.uuid)
    assert_nil RecordingStudioNotifications.reply_target(delivery_id: "not-a-delivery")
    assert_nil RecordingStudioNotifications.reply_target(delivery_id: nil)

    matched = RecordingStudioNotifications.reply_target(delivery_id: delivery.id, channel: :in_app)
    assert_equal notification, matched.notification
    assert_equal notification, RecordingStudioNotifications.reply_target(delivery_id: delivery.id, channel: "in_app").notification
    assert_nil RecordingStudioNotifications.reply_target(delivery_id: delivery.id, channel: :email)
    assert_nil RecordingStudioNotifications.reply_target(delivery_id: delivery.id, channel: " ")
  end

  test "a handler accepts the reply and the body is not stored" do
    notification = notify(thread_key: "thread-ok")
    seen = nil
    attachments = Object.new
    body = "secret reply #{SecureRandom.hex(4)}"
    register_handler do |notification:, recipient:, body:, attachments:|
      seen = { notification:, recipient:, body:, attachments: }
      RecordingStudioNotifications::ReplyResult.ok
    end
    RecordingStudioNotifications.register_notification_type(
      :inbound_reply_notice,
      label: "Inbound reply notice again",
      scope: :global,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    events = []
    result = nil
    subscribe(events) do
      result = reply(notification, body: body, attachments: attachments)
    end

    assert result.ok?
    assert_nil result.reason
    assert_equal notification, seen[:notification]
    assert_equal "thread-ok", seen[:notification].thread_key
    assert_equal @recipient, seen[:recipient]
    assert_equal body, seen[:body]
    assert_same attachments, seen[:attachments]
    stored = RecordingStudioNotifications::Reply.sole
    assert_equal "ok", stored.status
    assert_nil stored.reason
    assert_equal "email", stored.channel
    refute_includes stored.attributes.values.compact.map(&:to_s), body
    refute_includes RecordingStudioNotifications::Reply.column_names, "body"
    payload = events.sole
    assert_equal "inbound_reply_notice", payload.fetch(:type)
    assert_equal "email", payload.fetch(:channel)
    assert_equal "ok", payload.fetch(:outcome)
    assert_nil payload.fetch(:reason)
    refute payload.key?(:body)
    refute payload.key?(:thread_key)
    refute_includes payload.values.compact.map(&:to_s), body
  end

  test "a handler rejection is recorded and a replay is a duplicate" do
    notification = notify
    body = "please ignore #{SecureRandom.hex(4)}"
    calls = 0
    register_handler do
      calls += 1
      RecordingStudioNotifications::ReplyResult.rejected(:closed)
    end

    result = reply(notification, body: body, idempotency_key: "reply-closed")
    replay = reply(notification, body: body, idempotency_key: "reply-closed")

    assert result.rejected?
    assert_equal :closed, result.reason
    assert replay.duplicate?
    assert_equal 1, calls
    stored = RecordingStudioNotifications::Reply.sole
    assert_equal "rejected", stored.status
    assert_equal "closed", stored.reason
    refute_includes stored.attributes.values.compact.map(&:to_s), body
  end

  test "the same idempotency key can be claimed on another channel" do
    notification = notify
    register_handler { RecordingStudioNotifications::ReplyResult.ok }

    email = reply(notification, channel: :email, idempotency_key: "shared-key")
    chat = reply(notification, channel: :chat, idempotency_key: "shared-key")

    assert email.ok?
    assert chat.ok?
    assert_equal %w[chat email], RecordingStudioNotifications::Reply.order(:channel).pluck(:channel)
  end

  test "a mismatched recipient is rejected before the handler" do
    notification = notify
    calls = 0
    register_handler { calls += 1 }

    assert_no_difference -> { RecordingStudioNotifications::Reply.count } do
      result = reply(notification, recipient: @other)
      assert result.rejected?
      assert_equal :recipient_mismatch, result.reason
    end
    assert_equal 0, calls
  end

  test "a recipient who cannot see the notification is rejected" do
    owner = create_user("reply-owner")
    Current.actor = owner
    workspace = Workspace.create!(name: "Reply root #{SecureRandom.hex(4)}")
    root = RecordingStudio.create_root_recording!(workspace, actor: owner)
    bootstrap_owner!(root, owner)
    RecordingStudioNotifications.notification_types.register(
      :inbound_reply_rooted,
      label: "Inbound reply rooted",
      scope: :root,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    notification = RecordingStudioNotifications.notify(
      notification_type: :inbound_reply_rooted,
      recipient: @recipient,
      actor: owner,
      root_recording: root,
      title: "Rooted reply",
      idempotency_key: "reply-rooted-#{SecureRandom.hex(4)}",
      deliver_later: true
    )
    calls = 0
    register_handler(:inbound_reply_rooted) { calls += 1 }

    assert_not RecordingStudioNotifications::Services::NotificationAuthorization.visible_notification?(
      actor: @recipient,
      notification: notification
    )
    assert_no_difference -> { RecordingStudioNotifications::Reply.count } do
      result = reply(notification)
      assert result.rejected?
      assert_equal :not_visible, result.reason
    end
    assert_equal 0, calls
  end

  test "a recipient with a grant on the recording but not the root can reply" do
    owner = create_user("reply-recording-owner")
    root = reply_root(owner)
    conversation = conversation_recording(root, owner)
    grant!(conversation, @recipient, :view, manager: owner)
    notification = rooted_notification(root: root, recording: conversation, actor: owner)
    calls = 0
    register_handler(:inbound_reply_rooted) do
      calls += 1
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert RecordingStudioAccessible.authorized?(actor: @recipient, recording: conversation, role: :view)
    assert_not RecordingStudioAccessible.authorized?(actor: @recipient, recording: root, role: :view)
    assert_not RecordingStudioNotifications::Services::NotificationAuthorization.visible_notification?(
      actor: @recipient,
      notification: notification
    )
    inbox = RecordingStudioNotifications::Services::InboxScope.relation(
      recipient: @recipient,
      actor: @recipient,
      root_recording: root,
      inbox_scope: "all"
    )
    assert_not_includes inbox.pluck(:id), notification.id

    result = reply(notification)

    assert result.ok?, result.reason.inspect
    assert_nil result.reason
    assert_equal 1, calls
  end

  test "a recipient with neither a recording grant nor a root grant is rejected" do
    owner = create_user("reply-neither-owner")
    root = reply_root(owner)
    conversation = conversation_recording(root, owner)
    notification = rooted_notification(root: root, recording: conversation, actor: owner)
    calls = 0
    register_handler(:inbound_reply_rooted) do
      calls += 1
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert_no_difference -> { RecordingStudioNotifications::Reply.count } do
      result = reply(notification)
      assert result.rejected?
      assert_equal :not_visible, result.reason
    end
    assert_equal 0, calls
  end

  test "a recipient who can view the root can still reply" do
    owner = create_user("reply-root-owner")
    root = reply_root(owner)
    grant!(root, @recipient, :view, manager: owner)
    notification = rooted_notification(root: root, actor: owner)
    calls = 0
    register_handler(:inbound_reply_rooted) do
      calls += 1
      RecordingStudioNotifications::ReplyResult.ok
    end

    result = reply(notification)

    assert result.ok?
    assert_equal 1, calls
  end

  test "a non owner is rejected even with a grant on the recording" do
    owner = create_user("reply-mismatch-owner")
    root = reply_root(owner)
    conversation = conversation_recording(root, owner)
    grant!(conversation, @other, :view, manager: owner)
    notification = rooted_notification(root: root, recording: conversation, actor: owner)
    calls = 0
    register_handler(:inbound_reply_rooted) do
      calls += 1
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert_no_difference -> { RecordingStudioNotifications::Reply.count } do
      result = reply(notification, recipient: @other)
      assert result.rejected?
      assert_equal :recipient_mismatch, result.reason
    end
    assert_equal 0, calls
  end

  test "a type without a handler is not replyable" do
    notification = notify
    RecordingStudioNotifications.reply_handlers.clear!

    assert_not RecordingStudioNotifications.replyable?(:inbound_reply_notice)
    assert_no_difference -> { RecordingStudioNotifications::Reply.count } do
      result = reply(notification)
      assert result.rejected?
      assert_equal :not_replyable, result.reason
    end
  end

  test "a handler error rolls the claim back and the same key can succeed later" do
    notification = notify
    body = "secret reply #{SecureRandom.hex(4)}"
    io = StringIO.new
    register_handler { raise RuntimeError, body }
    failed = nil

    with_logger(io) do
      assert_no_difference -> { RecordingStudioNotifications::Reply.count } do
        failed = reply(notification, body: body, idempotency_key: "reply-retry")
      end
    end

    assert failed.failed?
    assert_equal :handler_error, failed.reason
    assert_includes io.string, "RuntimeError"
    refute_includes io.string, body

    calls = 0
    register_handler do
      calls += 1
      RecordingStudioNotifications::ReplyResult.ok
    end
    retried = reply(notification, body: body, idempotency_key: "reply-retry")

    assert retried.ok?
    assert_equal 1, calls
    assert_equal "ok", RecordingStudioNotifications::Reply.sole.status
  end

  test "a handler that returns something else fails and rolls the claim back" do
    notification = notify
    io = StringIO.new
    register_handler { "person@example.test" }
    result = nil

    with_logger(io) do
      assert_no_difference -> { RecordingStudioNotifications::Reply.count } do
        result = reply(notification, idempotency_key: "reply-invalid")
      end
    end

    assert result.failed?
    assert_equal :invalid_result, result.reason
    assert_includes io.string, "String"
    refute_includes io.string, "person@example.test"
  end

  test "a handler can see the claim and a duplicate does not call it again" do
    notification = notify
    seen = nil
    register_handler do
      seen = RecordingStudioNotifications::Reply.where(idempotency_key: "reply-claim").count
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert reply(notification, idempotency_key: "reply-claim").ok?
    assert_equal 1, seen

    calls = 0
    register_handler { calls += 1 }
    assert reply(notification, idempotency_key: "reply-claim").duplicate?
    assert_equal 0, calls
  end

  private

  def create_user(prefix)
    User.create!(
      email: "#{prefix}-#{SecureRandom.uuid}@example.test",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end

  def notify(thread_key: nil, idempotency_key: "reply-#{SecureRandom.hex(4)}")
    RecordingStudioNotifications.notify(
      notification_type: :inbound_reply_notice,
      recipient: @recipient,
      title: "Reply please",
      thread_key: thread_key,
      idempotency_key: idempotency_key,
      deliver_later: true
    )
  end

  def register_handler(type = :inbound_reply_notice, &block)
    RecordingStudioNotifications.register_reply_handler(type) do |notification:, recipient:, body:, attachments:|
      if block.parameters.empty?
        block.call
      else
        block.call(notification:, recipient:, body:, attachments:)
      end
    end
  end

  def reply(notification, recipient: @recipient, body: "Thanks", attachments: [], channel: :email, idempotency_key: "reply-#{SecureRandom.hex(4)}")
    RecordingStudioNotifications.handle_reply(
      notification: notification,
      recipient: recipient,
      body: body,
      attachments: attachments,
      channel: channel,
      idempotency_key: idempotency_key
    )
  end

  def subscribe(events, &block)
    callback = lambda do |_name, _start, _finish, _id, payload|
      events << payload
    end
    ActiveSupport::Notifications.subscribed(callback, "reply.recording_studio_notifications", &block)
  end

  def with_logger(io)
    original = Rails.logger
    Rails.logger = Logger.new(io)
    yield
  ensure
    Rails.logger = original
  end

  def bootstrap_owner!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    raise result.error if result.failure?
  end

  def reply_root(owner)
    Current.actor = owner
    workspace = Workspace.create!(name: "Reply root #{SecureRandom.hex(4)}")
    root = RecordingStudio.create_root_recording!(workspace, actor: owner)
    bootstrap_owner!(root, owner)
    root
  end

  def conversation_recording(root, owner)
    RecordingStudio.enable_capability(:accessible, on: Page)
    page = Page.create!(title: "Conversation #{SecureRandom.hex(4)}")
    RecordingStudio.record!(
      action: "created",
      recordable: page,
      root_recording: root,
      parent_recording: root,
      actor: owner
    ).recording
  end

  def rooted_notification(root:, actor:, recording: nil)
    RecordingStudioNotifications.notification_types.register(
      :inbound_reply_rooted,
      label: "Inbound reply rooted",
      scope: :root,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    RecordingStudioNotifications.notify(
      notification_type: :inbound_reply_rooted,
      recipient: @recipient,
      actor: actor,
      recording: recording,
      root_recording: root,
      title: "Rooted reply",
      idempotency_key: "reply-rooted-#{SecureRandom.hex(4)}",
      deliver_later: true
    )
  end

  def grant!(recording, actor, role, manager:)
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)

    configuration = RecordingStudioAccessible.configuration
    original = configuration.access_management_authorizer
    configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: manager
    )
    raise result.error if result.failure?
  ensure
    configuration.access_management_authorizer = original if configuration
  end
end
