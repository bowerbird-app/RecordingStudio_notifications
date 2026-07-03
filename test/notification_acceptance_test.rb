# frozen_string_literal: true

require "test_helper"

class NotificationAcceptanceTest < Minitest::Test
  FakeActor = Struct.new(:id)
  FakeNotification = Struct.new(:recipient, :root_recording, :recording)

  def setup
    @original_configuration = RecordingStudioNotifications.instance_variable_get(:@configuration)
    RecordingStudioNotifications.reset_configuration!
  end

  def teardown
    Object.send(:remove_const, :RecordingStudioAccessible) if defined?(RecordingStudioAccessible)
    RecordingStudioNotifications.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_notification_types_support_channels_scope_and_creation_action
    type = RecordingStudioNotifications.notification_types.register(
      :comment,
      label: "Comment",
      default_channels: [:in_app],
      required_channels: [:audit],
      available_channels: %i[in_app email audit],
      scope: :root,
      creation_action: :create_comment_notification
    )

    assert_equal [:in_app], type.default_channels
    assert_equal [:audit], type.required_channels
    assert_equal %i[in_app email audit], type.available_channels
    assert_equal %i[in_app email], type.optional_channels
    assert_equal :root, type.scope
    assert_equal :create_comment_notification, type.creation_action
  end

  def test_notification_type_scope_is_validated
    assert_raises(ArgumentError) do
      RecordingStudioNotifications.notification_types.register(:bad, label: "Bad", scope: :workspace)
    end
  end

  def test_explicit_empty_default_channels_are_preserved
    type = RecordingStudioNotifications.notification_types.register(
      :audit_only,
      label: "Audit only",
      default_channels: [],
      required_channels: [:audit],
      available_channels: [:audit]
    )

    assert_equal [], type.default_channels
    assert_equal [:audit], type.required_channels
    assert_equal [], type.optional_channels
  end

  def test_omitted_available_channels_allow_global_default_fallback
    type = RecordingStudioNotifications.notification_types.register(:fallback, label: "Fallback")

    assert_nil type.default_channels
    assert_nil type.available_channels
  end

  def test_preferences_model_limits_settings_to_optional_channels
    source = File.read(File.expand_path("../app/models/recording_studio_notifications/preference.rb", __dir__))

    assert_includes source, "optional_channels"
    assert_includes source, "enabled_for?"
    assert_includes source, "set!"
  end

  def test_notify_applies_required_channels_preferences_creation_auth_and_instrumentation
    source = File.read(File.expand_path("../lib/recording_studio_notifications/services/notify.rb", __dir__))

    assert_includes source, "type_definition.required_channels"
    assert_includes source, "Preference.enabled_for?"
    assert_includes source, "creation_action"
    assert_includes source, "notify.recording_studio_notifications"
    assert_includes source, "RootResolver.consistent?"
    assert_includes source, "default: requested.include?(channel)"
    assert_includes source, "enqueue_or_deliver!(notification) if should_deliver"
  end

  def test_delivery_uses_channel_architecture_and_instrumentation
    job = File.read(File.expand_path("../app/jobs/recording_studio_notifications/delivery_job.rb", __dir__))
    adapter = File.read(File.expand_path("../lib/recording_studio_notifications/channel_registry.rb", __dir__))

    assert_includes adapter, "class InAppAdapter"
    assert_includes job, "RecordingStudioNotifications.channels.fetch"
    assert_includes job, "delivery.mark_delivered! if delivery.reload.pending?"
    assert_includes job, "deliver.recording_studio_notifications"
  end

  def test_authorization_uses_accessible_for_root_visibility_and_preferences
    calls = []
    fake_accessible = Module.new do
      define_singleton_method(:authorized_action?) do |**kwargs|
        calls << kwargs
        kwargs[:action] == :view
      end
    end
    Object.const_set(:RecordingStudioAccessible, fake_accessible)

    actor = FakeActor.new("1")
    notification = FakeNotification.new(actor, Object.new, nil)

    assert RecordingStudioNotifications::Services::NotificationAuthorization.visible_notification?(
      actor: actor,
      notification: notification
    )
    assert_equal :view, calls.last.fetch(:action)

    refute RecordingStudioNotifications::Services::NotificationAuthorization.preferences_allowed?(
      actor: actor,
      recipient: actor
    )
    assert_equal :"recording_studio_notifications.manage_preferences", calls.last.fetch(:action)
  end

  def test_inbox_supports_all_and_current_root_with_rootless_notifications
    controller = File.read(File.expand_path("../app/controllers/recording_studio_notifications/notifications_controller.rb", __dir__))
    application_controller = File.read(File.expand_path("../app/controllers/recording_studio_notifications/application_controller.rb", __dir__))
    model = File.read(File.expand_path("../app/models/recording_studio_notifications/notification.rb", __dir__))
    initializer = File.read(File.expand_path("../test/dummy/config/initializers/recording_studio_notifications.rb", __dir__))

    assert_includes controller, 'params[:scope].presence_in(%w[all current_root])'
    assert_includes model, "for_current_root_inbox"
    assert_includes model, "rootless_or_global"
    assert_includes application_controller, "RecordingStudio::RootSwitchable::ControllerSupport"
    assert_includes application_controller, "actor || RecordingStudioNotifications.configuration.resolve_actor"
    assert_includes initializer, "config.current_root_resolver"
  end

  def test_settings_ui_and_routes_exist_without_bell_or_custom_css
    routes = File.read(File.expand_path("../config/routes.rb", __dir__))
    settings = File.read(File.expand_path("../app/views/recording_studio_notifications/settings/show.html.erb", __dir__))
    views = Dir[File.expand_path("../app/views/recording_studio_notifications/**/*.erb", __dir__)].map { |path| File.read(path) }.join("
")

    assert_includes routes, "resource :settings"
    assert_includes settings, "Notification settings"
    assert_includes settings, "Array(type.default_channels).include?(channel)"
    assert_includes views, "FlatPack::"
    refute_includes views, "notification_bell"
    refute_includes views, "<style"
  end

  def test_readme_documents_usage_and_integration
    readme = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme, "notify_each"
    assert_includes readme, "required_channels"
    assert_includes readme, "scope=current_root"
    assert_includes readme, "CaptainHook"
    assert_includes readme, "not RecordingStudio recordings or recordables"
  end
end
