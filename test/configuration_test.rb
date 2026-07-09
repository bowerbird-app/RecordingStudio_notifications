# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioNotifications::Configuration.new
  end

  def test_defaults_register_generic_type_and_in_app_channel
    assert_equal [:in_app], @configuration.default_channels
    assert @configuration.channels.registered?(:in_app)
    assert @configuration.notification_types.registered?(:generic)
    assert_equal :bell, @configuration.notification_types.fetch(:generic).icon
    assert_equal true, @configuration.deliver_later
    assert_equal 60, @configuration.polling_interval_seconds
  end

  def test_merge_updates_known_attributes_and_ignores_unknown_keys
    @configuration.merge!(
      "allowed_url_hosts" => ["example.com"],
      queue_name: :notifications,
      polling_interval_seconds: 30,
      unknown: true
    )

    assert_equal ["example.com"], @configuration.allowed_url_hosts
    assert_equal :notifications, @configuration.queue_name
    assert_equal 30, @configuration.polling_interval_seconds
    refute_respond_to @configuration, :unknown
  end

  def test_notification_type_registry_requires_non_blank_keys
    assert_raises(ArgumentError) do
      @configuration.notification_types.register("", label: "Blank")
    end
  end

  def test_channel_registry_requires_deliver_adapter
    assert_raises(ArgumentError) do
      @configuration.channels.register(:broken, Object.new)
    end
  end

  def test_to_h_reports_runtime_registries
    result = @configuration.to_h

    assert_includes result.fetch(:notification_types), :generic
    assert_includes result.fetch(:channels), :in_app
  end
end
