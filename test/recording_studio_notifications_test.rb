# frozen_string_literal: true

require "test_helper"

class RecordingStudioNotificationsTest < Minitest::Test
  def test_version_and_engine_exist
    refute_nil ::RecordingStudioNotifications::VERSION
    assert_kind_of Class, ::RecordingStudioNotifications::Engine
  end

  def test_public_api_methods_exist
    assert_respond_to RecordingStudioNotifications, :notify
    assert_respond_to RecordingStudioNotifications, :notify_each
    assert_respond_to RecordingStudioNotifications, :register_notification_type
    assert_respond_to RecordingStudioNotifications, :register_channel
  end

  def test_gemspec_uses_recording_studio_notifications_identity
    gemspec = File.read(File.expand_path("../recording_studio_notifications.gemspec", __dir__))

    assert_includes gemspec, 'spec.name        = "recording_studio_notifications"'
    assert_includes gemspec, "RecordingStudioNotifications::VERSION"
    refute_includes gemspec, "GemTemplate"
  end

  def test_engine_routes_notifications_as_root
    routes = File.read(File.expand_path("../config/routes.rb", __dir__))

    assert_includes routes, "resources :notifications"
    assert_includes routes, "get :menu"
    assert_includes routes, "resource :settings"
    assert_includes routes, 'root "notifications#index"'
  end

  def test_migration_uses_uuid_polymorphic_columns_and_idempotency
    migration = File.read(File.expand_path("../db/migrate/20250101000001_create_recording_studio_notifications.rb",
                                           __dir__))

    assert_includes migration, "id: :uuid"
    assert_includes migration, "t.uuid :recipient_id"
    assert_includes migration, "t.uuid :actor_id"
    assert_includes migration, "t.uuid :notifiable_id"
    assert_includes migration, "idx_rsn_notifications_idempotency"
    assert_includes migration, "recording_studio_notifications_preferences"
  end

  def test_dummy_app_mounts_engine_and_registers_example_types
    routes = File.read(File.expand_path("dummy/config/routes.rb", __dir__))
    initializer = File.read(File.expand_path("dummy/config/initializers/recording_studio_notifications.rb", __dir__))
    controllers_index = File.read(File.expand_path("dummy/app/javascript/controllers/index.js", __dir__))
    polling_controller = File.read(File.expand_path("dummy/app/javascript/controllers/notification_polling_controller.js", __dir__))

    assert_includes routes, "mount RecordingStudioNotifications::Engine"
    assert_includes initializer, "config.notification_types.register"
    assert_includes initializer, ":page_comment"
    assert_includes initializer, ":page_created"
    assert_match(
      /:workspace_change,.*allowed_cadences: %i\[every_notification daily monthly\]/m,
      initializer
    )
    assert_match(
      /:workspace_digest,.*allowed_cadences: %i\[every_notification monthly\],.*default_cadence: :monthly/m,
      initializer
    )
    assert_includes controllers_index, 'lazyLoadControllersFrom("controllers/flat_pack", application)'
    assert_includes polling_controller, "class extends Controller"
    assert_includes polling_controller, "this.refresh()"
  end

  def test_engine_views_use_flatpack_menu_component_and_scoped_settings_layering
    views = Dir[File.expand_path("../app/views/recording_studio_notifications/**/*.erb", __dir__)].map do |path|
      File.read(path)
    end.join("\n")

    assert_includes views, "FlatPack::"
    assert_includes views, "FlatPack::Notification::Component"
    assert_includes views, ".rsn-settings-accordion"
    assert_includes views, "overflow: visible"
  end
end
