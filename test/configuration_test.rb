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
    generic_type = @configuration.notification_types.fetch(:generic)
    assert_equal :bell, generic_type.icon
    assert_equal [:individual], generic_type.allowed_cadences
    assert_equal :individual, generic_type.default_cadence
    assert_nil generic_type.required_cadence
    assert_nil generic_type.visible_to
    assert generic_type.visible_to?(Object.new)
    assert_equal true, generic_type.inbox
    assert_equal 1.year, @configuration.unsubscribe_expires_in
    assert_equal 1.year, @configuration.to_h.fetch(:unsubscribe_expires_in)
    assert_equal true, @configuration.deliver_later
    assert_equal 60, @configuration.polling_interval_seconds
    assert_equal 15.minutes, @configuration.rollup_reservation_timeout
    assert_equal false, @configuration.rollup_delivery_enabled
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

  def test_inbox_defaults_true_and_rejects_a_required_in_app_channel
    hidden = @configuration.notification_types.register(
      :inbox_hidden,
      label: "Inbox hidden",
      inbox: false,
      default_channels: [:in_app],
      available_channels: [:in_app]
    )
    assert_equal false, hidden.inbox

    error = assert_raises(ArgumentError) do
      @configuration.notification_types.register(
        :inbox_required,
        label: "Inbox required",
        inbox: false,
        required_channels: [:in_app],
        available_channels: [:in_app]
      )
    end
    assert_equal "inbox cannot be false when in_app is a required channel", error.message
    refute @configuration.notification_types.registered?(:inbox_required)
  end

  def test_merge_sets_unsubscribe_expiry
    @configuration.merge!("unsubscribe_expires_in" => 2.days)

    assert_equal 2.days, @configuration.unsubscribe_expires_in
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

  def test_merge_ignores_a_value_that_cannot_be_enumerated
    @configuration.queue_name = :keep

    @configuration.merge!(nil)

    assert_equal :keep, @configuration.queue_name
  end

  def test_resolve_actor_calls_the_resolver
    @configuration.actor_resolver = -> { :current_actor }

    assert_equal :current_actor, @configuration.resolve_actor

    @configuration.actor_resolver = nil

    assert_nil @configuration.resolve_actor
  end

  def test_resolve_current_root_uses_current_recording_and_ignores_a_missing_controller
    controller = Object.new
    controller.define_singleton_method(:current_recording) { :selected_root }

    assert_equal :selected_root, @configuration.resolve_current_root(controller: controller)
    assert_nil @configuration.resolve_current_root(controller: nil)
  end

  def test_layout_accepts_nil_false_a_name_and_a_keyword_callable
    assert_nil @configuration.layout

    @configuration.layout = false
    assert_equal false, @configuration.layout

    @configuration.layout = "admin"
    assert_equal "admin", @configuration.layout

    callable = ->(controller:) { controller.class.name }
    @configuration.layout = callable
    assert_equal callable, @configuration.layout

    assert_raises(ArgumentError) { @configuration.layout = "  " }
    assert_equal callable, @configuration.layout
    assert_raises(ArgumentError) { @configuration.layout = ->(controller) { "admin-#{controller.class}" } }
    assert_equal callable, @configuration.layout
    assert_raises(ArgumentError) { @configuration.layout = Object.new }
    assert_equal callable, @configuration.layout
  end

  def test_controllers_do_not_hardcode_a_recording_studio_layout
    root = File.expand_path("..", __dir__)

    assert_empty RecordingStudio::Layout.hardcoded_layout_paths(root)
  end

  def test_to_h_reports_runtime_registries
    result = @configuration.to_h

    assert_includes result.fetch(:notification_types), :generic
    assert_includes result.fetch(:channels), :in_app
  end
end
