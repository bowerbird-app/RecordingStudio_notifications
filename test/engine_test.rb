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

  def test_admin_table_wrap_is_registered_with_admin
    engine = File.read(File.expand_path("../lib/recording_studio_notifications/engine.rb", __dir__))

    assert_includes engine, "recording_studio_notifications/admin/table_wrap_helper"
    assert_includes engine, "prepend_admin_table_wrap_views!"
    assert_includes engine, 'controller.prepend_view_path(view_path)'
    assert_includes engine, "RecordingStudioNotifications::Admin::TableWrapHelper"
  end

  private

  def find_initializer(name)
    RecordingStudioNotifications::Engine.initializers.find { |initializer| initializer.name == name } ||
      flunk("Expected initializer #{name.inspect}")
  end
end
