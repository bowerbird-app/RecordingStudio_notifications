# frozen_string_literal: true

require "test_helper"

class PublicApiTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioNotifications.instance_variable_get(:@configuration)
    RecordingStudioNotifications.reset_configuration!
  end

  def teardown
    RecordingStudioNotifications.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_register_notification_type_delegates_to_registry
    RecordingStudioNotifications.register_notification_type(:comment, label: "Comment")

    assert RecordingStudioNotifications.notification_types.registered?(:comment)
  end

  def test_register_channel_delegates_to_registry
    adapter = Class.new do
      def deliver(notification:, delivery:); end
    end.new

    RecordingStudioNotifications.register_channel(:test_channel, adapter)

    assert RecordingStudioNotifications.channels.registered?(:test_channel)
  end
end
