# frozen_string_literal: true

require "test_helper"

class DeliveryPayloadTest < Minitest::Test
  NotificationDouble = Struct.new(:notification_type, :title, :body, :url)

  def setup
    RecordingStudioNotifications.delivery_payload_resolvers.clear!
    @notification = NotificationDouble.new(:generic, "Persisted title", "Persisted body", "/persisted")
    @delivery = Object.new
  end

  def teardown
    RecordingStudioNotifications.delivery_payload_resolvers.clear!
  end

  def test_missing_resolver_returns_the_persisted_notification_payload
    payload = RecordingStudioNotifications.delivery_payload_for(notification: @notification, delivery: @delivery)

    assert_instance_of RecordingStudioNotifications::DeliveryPayload, payload
    assert_equal "Persisted title", payload.title
    assert_equal "Persisted body", payload.body
    assert_equal "/persisted", payload.url
  end

  def test_hash_resolvers_accept_symbol_and_string_keys
    RecordingStudioNotifications.register_delivery_payload_resolver(:generic) do
      { title: "Symbol title", "body" => "String body", url: "/symbol" }
    end

    payload = RecordingStudioNotifications.delivery_payload_for(notification: @notification, delivery: @delivery)

    assert_equal "Symbol title", payload.title
    assert_equal "String body", payload.body
    assert_equal "/symbol", payload.url
  end

  def test_delivery_payload_instances_pass_through
    original = RecordingStudioNotifications::DeliveryPayload.new(title: "Ready", body: "Body", url: "/ready")
    RecordingStudioNotifications.register_delivery_payload_resolver(:generic) { original }

    assert_same original, RecordingStudioNotifications.delivery_payload_for(notification: @notification, delivery: @delivery)
  end

  def test_resolver_errors_and_unknown_return_values_raise_delivery_payload_error
    RecordingStudioNotifications.register_delivery_payload_resolver(:generic) { raise "resolver down" }

    error = assert_raises(RecordingStudioNotifications::DeliveryPayloadError) do
      RecordingStudioNotifications.delivery_payload_for(notification: @notification, delivery: @delivery)
    end
    assert_equal "delivery payload resolution failed", error.message

    RecordingStudioNotifications.delivery_payload_resolvers.clear!
    RecordingStudioNotifications.register_delivery_payload_resolver(:generic) { "not a payload" }

    assert_raises(RecordingStudioNotifications::DeliveryPayloadError) do
      RecordingStudioNotifications.delivery_payload_for(notification: @notification, delivery: @delivery)
    end
  end

  def test_register_requires_a_block_and_blank_types_are_not_registered
    assert_raises(ArgumentError) do
      RecordingStudioNotifications.register_delivery_payload_resolver(:generic)
    end

    refute RecordingStudioNotifications.delivery_payload_resolvers.registered?(" ")
    refute RecordingStudioNotifications.delivery_payload_resolvers.registered?(nil)
  end

  def test_install_initializer_template_registers_the_generic_type
    original = RecordingStudioNotifications.instance_variable_get(:@configuration)
    RecordingStudioNotifications.reset_configuration!

    load File.expand_path(
      "../lib/generators/recording_studio_notifications/install/templates/recording_studio_notifications_initializer.rb",
      __dir__
    )

    generic = RecordingStudioNotifications.notification_types.fetch(:generic)
    assert_equal "Default in-app notification", generic.description
    assert_equal :optional_root, generic.scope
  ensure
    RecordingStudioNotifications.instance_variable_set(:@configuration, original)
  end
end
