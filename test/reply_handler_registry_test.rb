# frozen_string_literal: true

require "test_helper"

class ReplyHandlerRegistryTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioNotifications.instance_variable_get(:@configuration)
    @original_handlers = RecordingStudioNotifications.instance_variable_get(:@reply_handlers)
    RecordingStudioNotifications.reset_configuration!
    RecordingStudioNotifications.instance_variable_set(:@reply_handlers, nil)
  end

  def teardown
    RecordingStudioNotifications.instance_variable_set(:@configuration, @original_configuration)
    RecordingStudioNotifications.instance_variable_set(:@reply_handlers, @original_handlers)
  end

  def test_re_registering_a_type_keeps_the_handler
    handler = RecordingStudioNotifications.register_reply_handler(:message_received) do |notification:, recipient:, body:, attachments:|
      [notification, recipient, body, attachments]
    end
    RecordingStudioNotifications.register_notification_type(:message_received, label: "Message")
    RecordingStudioNotifications.register_notification_type(:message_received, label: "Message again")

    assert RecordingStudioNotifications.replyable?(:message_received)
    assert_equal handler, RecordingStudioNotifications.reply_handlers.fetch(:message_received)
    assert_equal [:notice, :person, "hello", []], handler.call(
      notification: :notice,
      recipient: :person,
      body: "hello",
      attachments: []
    )
  end

  def test_registering_a_handler_again_replaces_it
    RecordingStudioNotifications.register_reply_handler(:message_received) do |notification:, recipient:, body:, attachments:|
      [notification, recipient, body, attachments, :first]
    end
    replacement = RecordingStudioNotifications.register_reply_handler(:message_received) do |notification:, recipient:, body:, attachments:|
      [notification, recipient, body, attachments, :second]
    end

    assert_equal replacement, RecordingStudioNotifications.reply_handlers.fetch(" message_received ")
    assert_equal [:notice, :person, "hello", nil, :second], replacement.call(
      notification: :notice,
      recipient: :person,
      body: "hello",
      attachments: nil
    )
  end

  def test_reset_configuration_keeps_handlers
    RecordingStudioNotifications.register_reply_handler(:message_received) do |notification:, recipient:, body:, attachments:|
      [notification, recipient, body, attachments]
    end

    RecordingStudioNotifications.reset_configuration!

    assert RecordingStudioNotifications.replyable?(:message_received)
    refute RecordingStudioNotifications.notification_types.registered?(:message_received)
  end

  def test_a_type_without_a_handler_is_not_replyable
    refute RecordingStudioNotifications.replyable?(:message_received)
    refute RecordingStudioNotifications.replyable?(nil)
    refute RecordingStudioNotifications.replyable?(" ")

    error = assert_raises(ArgumentError) do
      RecordingStudioNotifications.register_reply_handler(:message_received)
    end
    assert_equal "reply handler block is required", error.message
  end
end

class ReplyResultTest < Minitest::Test
  def test_outcomes_carry_symbol_reasons_only
    ok = RecordingStudioNotifications::ReplyResult.ok
    assert ok.ok?
    assert_nil ok.reason

    rejected = RecordingStudioNotifications::ReplyResult.rejected(:closed)
    assert rejected.rejected?
    assert_equal :closed, rejected.reason

    duplicate = RecordingStudioNotifications::ReplyResult.duplicate
    assert duplicate.duplicate?
    assert_nil duplicate.reason

    failed = RecordingStudioNotifications::ReplyResult.failed(:handler_error)
    assert failed.failed?
    assert_equal :handler_error, failed.reason

    assert_raises(ArgumentError) { RecordingStudioNotifications::ReplyResult.rejected("person@example.test") }
    assert_raises(ArgumentError) { RecordingStudioNotifications::ReplyResult.failed("person@example.test") }
  end
end
