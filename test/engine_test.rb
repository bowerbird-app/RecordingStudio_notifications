# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioNotifications.instance_variable_get(:@configuration)
    RecordingStudioNotifications.reset_configuration!
  end

  def teardown
    RecordingStudioNotifications.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_load_config_merges_yaml_and_config_x
    xcfg = Struct.new(:recording_studio_notifications).new({ queue_name: :critical })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { default_channels: [:in_app], allowed_url_hosts: ["example.com"] }
      end
    end.new(app_config)

    find_initializer("recording_studio_notifications.load_config").block.call(app)

    assert_equal [:in_app], RecordingStudioNotifications.configuration.default_channels
    assert_equal ["example.com"], RecordingStudioNotifications.configuration.allowed_url_hosts
    assert_equal :critical, RecordingStudioNotifications.configuration.queue_name
  end

  def test_engine_is_isolated
    assert_kind_of Class, RecordingStudioNotifications::Engine
    assert_includes File.read(File.expand_path("../lib/recording_studio_notifications/engine.rb", __dir__)),
                    "isolate_namespace RecordingStudioNotifications"
  end

  def test_engine_registers_metrics_and_does_not_expose_api
    engine = File.read(File.expand_path("../lib/recording_studio_notifications/engine.rb", __dir__))

    assert_includes engine, 'initializer "recording_studio_notifications.metrics"'
    assert_includes engine, "RecordingStudioNotifications::Metrics.register!"
    refute_includes engine, "RecordingStudioMetrics::Api.register!"
  end

  def test_engine_defines_default_view_action_without_overriding_a_host
    engine = File.read(File.expand_path("../lib/recording_studio_notifications/engine.rb", __dir__))

    assert_includes engine, "register_action(\n          :view,"
    assert_includes engine, "define_default_view_accessible_action"
    assert_includes engine, "authorized?(actor: actor, recording: recording, role: :view)"
    assert_includes engine, "return if RecordingStudioAccessible.respond_to?(:action_defined?) &&"
  end

  def test_load_config_uses_each_pair_when_config_x_has_no_to_h
    ordered = Object.new
    ordered.define_singleton_method(:each_pair) { |&block| block.call("queue_name", :from_ordered_options) }
    app = config_app(recording_studio_notifications: ordered)

    find_initializer("recording_studio_notifications.load_config").block.call(app)

    assert_equal :from_ordered_options, RecordingStudioNotifications.configuration.queue_name
  end

  def test_load_config_ignores_yaml_and_ordered_options_that_raise
    missing = config_app(recording_studio_notifications: Object.new)
    missing.define_singleton_method(:config_for) { |_name| raise "yaml missing" }
    find_initializer("recording_studio_notifications.load_config").block.call(missing)

    yaml = Object.new
    yaml.define_singleton_method(:each) { raise "yaml each failed" }
    ordered = Object.new
    ordered.define_singleton_method(:each_pair) { raise "ordered options failed" }
    app = config_app(recording_studio_notifications: ordered)
    app.define_singleton_method(:config_for) { |_name| yaml }
    find_initializer("recording_studio_notifications.load_config").block.call(app)

    assert_equal :default, RecordingStudioNotifications.configuration.queue_name
  end

  def test_extensions_apply_once_and_skip_a_missing_target
    widget = Class.new
    widget.define_singleton_method(:name) { "CoverageWidget" }
    model_calls = 0
    RecordingStudioNotifications.configuration.hooks.extend_model(:CoverageWidget) do
      model_calls += 1
      def coverage_widget_ready?
        true
      end
    end
    RecordingStudioNotifications.configuration.hooks.extend_controller(:CoverageWidget) do
      def coverage_controller_ready?
        true
      end
    end

    assert_nil RecordingStudioNotifications::Engine.send(:apply_extensions, nil, [])
    RecordingStudioNotifications::Engine.apply_model_extensions(widget)
    RecordingStudioNotifications::Engine.apply_model_extensions(widget)
    RecordingStudioNotifications::Engine.apply_controller_extensions(widget)

    assert_equal 1, model_calls
    assert widget.new.coverage_widget_ready?
    assert widget.new.coverage_controller_ready?
  end

  def test_engine_loads_only_english_locale_files
    locale_dir = RecordingStudioNotifications::Engine.root.join("config/locales")

    assert_equal ["en.yml"], Dir.children(locale_dir).sort
    refute(Dir.children(locale_dir).any? { |name| name.end_with?("fr.yml") })
  end

  def test_lib_sources_do_not_append_to_i18n_load_path
    ruby_files = Dir[File.expand_path("../lib/**/*.rb", __dir__)]

    refute_empty ruby_files, "expected lib/**/*.rb files to scan"

    ruby_files.each do |path|
      source = File.read(path)

      refute_includes source, "i18n.load_path",
                      "#{path} must not touch config.i18n.load_path (Rails engines load config/locales automatically)"
      refute_includes source, "I18n.load_path",
                      "#{path} must not append to I18n.load_path (that re-adds gem English after host overrides)"
    end
  end

  private

  def find_initializer(name)
    RecordingStudioNotifications::Engine.initializers.find { |initializer| initializer.name == name } ||
      flunk("Expected initializer #{name.inspect}")
  end

  def config_app(recording_studio_notifications:)
    config_x = Object.new
    config_x.define_singleton_method(:recording_studio_notifications) { recording_studio_notifications }
    app_config = Object.new
    app_config.define_singleton_method(:x) { config_x }
    app = Object.new
    app.define_singleton_method(:config) { app_config }
    app
  end
end
