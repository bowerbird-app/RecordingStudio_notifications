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

  def test_notification_types_support_channels_scope_cadence_and_creation_action
    type = RecordingStudioNotifications.notification_types.register(
      :comment,
      label: "Comment",
      category: :page,
      icon: :chat_bubble_left_ellipsis,
      default_channels: [:in_app],
      required_channels: [:audit],
      available_channels: %i[in_app email audit],
      allowed_cadences: %i[every_notification daily weekly],
      default_cadence: :daily,
      scope: :root,
      creation_action: :create_comment_notification
    )

    assert_equal [:in_app], type.default_channels
    assert_equal [:audit], type.required_channels
    assert_equal %i[in_app email audit], type.available_channels
    assert_equal %i[in_app email], type.optional_channels
    assert_equal %i[every_notification daily weekly], type.allowed_cadences
    assert_equal :daily, type.default_cadence
    assert_equal :page, type.category
    assert_equal :chat_bubble_left_ellipsis, type.icon
    assert_equal :root, type.scope
    assert_equal :create_comment_notification, type.creation_action
  end

  def test_notification_type_scope_is_validated
    assert_raises(ArgumentError) do
      RecordingStudioNotifications.notification_types.register(:bad, label: "Bad", scope: :workspace)
    end
  end

  def test_notification_type_cadences_are_validated
    assert_raises(ArgumentError) do
      RecordingStudioNotifications.notification_types.register(
        :bad_cadence,
        label: "Bad cadence",
        allowed_cadences: [:hourly]
      )
    end

    assert_raises(ArgumentError) do
      RecordingStudioNotifications.notification_types.register(
        :missing_default_cadence,
        label: "Missing default cadence",
        allowed_cadences: [:daily],
        default_cadence: :weekly
      )
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

  def test_omitted_icon_defaults_to_bell
    type = RecordingStudioNotifications.notification_types.register(:fallback_icon, label: "Fallback icon")

    assert_equal :bell, type.icon
    assert_equal [:every_notification], type.allowed_cadences
    assert_equal :every_notification, type.default_cadence
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

  def test_inbox_is_current_root_only_with_rootless_notifications
    controller = File.read(File.expand_path(
                             "../app/controllers/recording_studio_notifications/notifications_controller.rb", __dir__
                           ))
    routes = File.read(File.expand_path("../config/routes.rb", __dir__))
    application_controller = File.read(File.expand_path(
                                         "../app/controllers/recording_studio_notifications/application_controller.rb", __dir__
                                       ))
    model = File.read(File.expand_path("../app/models/recording_studio_notifications/notification.rb", __dir__))
    index_view = File.read(File.expand_path("../app/views/recording_studio_notifications/notifications/index.html.erb",
                                           __dir__))
    notification_partial = File.read(File.expand_path(
      "../app/views/recording_studio_notifications/notifications/_notification.html.erb", __dir__
    ))
    initializer = File.read(File.expand_path("../test/dummy/config/initializers/recording_studio_notifications.rb",
                                             __dir__))
    accessible_initializer = File.read(File.expand_path(
                                         "../test/dummy/config/initializers/recording_studio_accessible.rb", __dir__
                                       ))

    assert_includes controller, "@inbox_scope = notifications_inbox_scope"
    assert_includes controller, "def menu"
    assert_includes controller, "@inbox_scope = \"all\""
    assert_includes controller, "polling_interval_seconds"
    assert_includes routes, "get :menu"
    assert_includes controller, "def recording_studio_root_switchable_scope_key"
    assert_includes model, "for_current_root_inbox"
    assert_includes model, "rootless_or_global"
    assert_includes application_controller, "RecordingStudio::RootSwitchable::ControllerSupport"
    assert_includes application_controller, "actor || RecordingStudioNotifications.configuration.resolve_actor"
    assert_includes index_view, "icon: \"cog\""
    assert_includes notification_partial, "FlatPack::Timestamp::Component.new("
    assert_includes notification_partial, "shorten_timestamp: true"
    refute_includes index_view, "inbox_scope: :all"
    refute_includes index_view, "inbox_scope: :current_root"
    refute_includes index_view, "Total:"
    refute_includes index_view, "Unread:"
    assert_includes initializer, "config.current_root_resolver"
    assert_includes accessible_initializer, "current_root.id.to_s == recording.id.to_s"
  end

  def test_settings_ui_and_routes_exist_with_scoped_dropdown_layering
    routes = File.read(File.expand_path("../config/routes.rb", __dir__))
    controller = File.read(File.expand_path("../app/controllers/recording_studio_notifications/settings_controller.rb", __dir__))
    settings = File.read(File.expand_path("../app/views/recording_studio_notifications/settings/show.html.erb",
                                          __dir__))
    views = Dir[File.expand_path("../app/views/recording_studio_notifications/**/*.erb", __dir__)].map do |path|
      File.read(path)
    end.join("
")

    assert_includes controller, "prepare_settings_view"
    assert_includes controller, "grouped_notification_types"
    assert_includes controller, "notification_type_category"
    assert_includes controller, "flat_notification_types"
    assert_includes controller, "channel_select_options_map"
    assert_includes controller, "selected_channels_map"
    assert_includes controller, "cadence_select_options_map"
    assert_includes controller, "selected_cadences_map"
    assert_includes controller, "CadencePreference.set!"
    assert_includes controller, "@cadence_preferences_available = CadencePreference.table_exists?"
    assert_includes controller, "type.allowed_cadences"
    assert_includes controller, ".group_by { |type| notification_type_category(type) }"
    assert_includes controller, "next false if type.key == :generic"
    assert_includes controller, "type.optional_channels.any? || type.required_channels.any?"
    assert_includes controller, "Array(submitted[type.key.to_s]).flatten.map(&:to_s).reject(&:blank?)"
    assert_includes controller, "selected_channels = [] if selected_channels.include?(\"__none__\")"
    assert_includes controller, "disabled: type.required_channels.include?(channel)"
    assert_includes controller, "[\"None\", \"__none__\"]"
    assert_includes routes, "resource :settings"
    assert_includes settings, "Notification settings"
    assert_includes settings, "FlatPack::Accordion::Component.new"
    assert_includes settings, 'accordion.item(id: "settings-category-#{category}"'
    assert_includes settings, "FlatPack::Select::Component.new"
    assert_includes settings, "@notification_type_groups.each do |category, types|"
    assert_includes settings, "category.to_s.titleize"
    assert_includes settings, "disabled: type.optional_channels.empty?"
    assert_includes settings, "Required channels only"
    assert_includes settings, "multiple: true"
    assert_includes settings, "searchable: true"
    assert_includes settings, 'name: "cadences[#{type.key}]"'
    assert_includes settings, "Delivery cadence"
    assert_includes settings, "@cadence_select_options"
    assert_includes views, "FlatPack::"
    refute_includes views, "notification_bell"
    refute_includes settings, "check_box_tag"
    refute_includes settings, "hidden_field_tag"
    assert_includes settings, ".rsn-settings-accordion"
    assert_includes settings, "overflow: visible"
  end

  def test_dummy_top_nav_uses_flatpack_notification_component
    helper = File.read(File.expand_path("../test/dummy/app/helpers/application_helper.rb", __dir__))
    top_nav = File.read(File.expand_path("../test/dummy/app/views/layouts/flat_pack/_top_nav.html.erb", __dir__))
    tailwind = File.read(File.expand_path("../test/dummy/app/assets/tailwind/application.css", __dir__))
    menu_helper = File.read(File.expand_path("../app/helpers/recording_studio_notifications/menu_helper.rb", __dir__))
    menu_partial = File.read(File.expand_path("../app/views/recording_studio_notifications/notifications/_menu_component.html.erb",
                                              __dir__))
    polling_controller = File.read(File.expand_path(
      "../test/dummy/app/javascript/controllers/notification_polling_controller.js", __dir__
    ))

    assert_includes helper, "include RecordingStudioNotifications::MenuHelper"
    assert_includes helper, "def demo_notification_path"
    assert_includes helper, "def demo_notifications"
    assert_includes helper, "recording_studio_notifications_async_menu(recipient: current_user, limit: limit)"
    assert_includes menu_helper, "notification_polling_url_value"
    assert_includes menu_helper, "notification_polling_interval_value"
    assert_includes menu_helper, "notification_polling_limit_value"
    assert_includes menu_partial, "FlatPack::Notification::Component"
    assert_includes polling_controller, "this.refresh()"
    assert_includes polling_controller, "setInterval"
    assert_includes polling_controller, "polling_interval_seconds"
    assert_includes top_nav, "recording_studio_notifications_menu"
    assert_includes tailwind, '[id^="flat-pack-notification-"][id$="-popover"] .max-h-96'
  end

  def test_readme_documents_usage_and_integration
    readme = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme, "notify_each"
    assert_includes readme, "required_channels"
    assert_includes readme, "Current-root inbox behavior"
    assert_includes readme, "CaptainHook"
    assert_includes readme, "not RecordingStudio recordings or recordables"
  end

  def test_configuration_docs_explain_cadence_options
    config_docs = File.read(File.expand_path("../test/dummy/app/views/docs/config.html.erb", __dir__))
    cadence_preference = File.read(File.expand_path(
      "../app/models/recording_studio_notifications/cadence_preference.rb", __dir__
    ))

    assert_includes config_docs, "allowed_cadences:"
    assert_includes config_docs, "default_cadence:"
    assert_includes config_docs, ":biweekly"
    assert_includes cadence_preference, "is not allowed for this notification type"
    assert_includes cadence_preference, "cadence_for"
  end

  def test_digest_schema_and_models_preserve_source_notification_boundaries
    digest = File.read(File.expand_path(
      "../app/models/recording_studio_notifications/notification_digest.rb", __dir__
    ))
    digest_item = File.read(File.expand_path(
      "../app/models/recording_studio_notifications/notification_digest_item.rb", __dir__
    ))
    notification = File.read(File.expand_path(
      "../app/models/recording_studio_notifications/notification.rb", __dir__
    ))
    digest_delivery = File.read(File.expand_path(
      "../lib/recording_studio_notifications/services/digest_delivery.rb", __dir__
    ))
    digest_scheduler = File.read(File.expand_path(
      "../app/jobs/recording_studio_notifications/digest_scheduler_job.rb", __dir__
    ))
    digest_controller = File.read(File.expand_path(
      "../app/controllers/recording_studio_notifications/digests_controller.rb", __dir__
    ))
    digest_view = File.read(File.expand_path(
      "../app/views/recording_studio_notifications/digests/show.html.erb", __dir__
    ))
    digest_task = File.read(File.expand_path(
      "../lib/tasks/recording_studio_notifications.rake", __dir__
    ))
    migration = File.read(File.expand_path(
      "../db/migrate/20260710001000_create_recording_studio_notification_digests.rb", __dir__
    ))
    config_docs = File.read(File.expand_path("../test/dummy/app/views/docs/config.html.erb", __dir__))

    assert_includes digest, "STATUSES = %w[pending delivered cancelled]"
    assert_includes digest, "foreign_key: :digest_id"
    assert_includes digest, "has_many :source_notifications"
    assert_includes digest, "period_ends_after_start"
    assert_includes digest_item, "notification_matches_digest"
    assert_includes digest_item, "must match the digest root recording"
    assert_includes notification, "has_one :digest_item"
    assert_includes migration, "COALESCE(root_recording_id"
    assert_includes migration, "idx_rsn_pending_digest_bucket"
    assert_includes migration, "idx_rsn_digest_items_notification"
    assert_includes config_docs, "Consolidated Notification Data Model"
    assert_includes config_docs, "NotificationDigestItem"
    assert_includes config_docs, "bypass_digest: true"
    assert_includes config_docs, "DigestSchedulerJob.perform_later"
    assert_includes config_docs, "Digest Summary Presentation"
    assert_includes config_docs, "digest_summary_presenter"
    assert_includes digest_delivery, "digest-summary-\#{@digest.id}"
    assert_includes digest_delivery, "bypass_digest: true"
    assert_includes digest_delivery, "status: \"delivered\""
    assert_includes digest_delivery, "RecordingStudioAccessible.authorized?"
    assert_includes digest_scheduler, "Services::DigestDelivery.call"
    assert_includes digest_controller, "PER_PAGE = 25"
    assert_includes digest_controller, "digest_visible?"
    assert_includes digest_controller, "visible_notification?(notification)"
    assert_includes digest_view, "No accessible events remain in this digest."
    assert_includes digest_task, "FORCE=1"
    assert_includes digest_task, "available only in development"
    assert_includes config_docs, "Local Digest Demo"
    assert_includes config_docs, "recording_studio_notifications:deliver_due_digests"
    assert_includes config_docs, "Upgrade Compatibility"
    assert_includes File.read(File.expand_path("../README.md", __dir__)), "Existing notification types continue to deliver immediately"
    assert_includes File.read(File.expand_path("../CHANGELOG.md", __dir__)), "default `:every_notification` cadence"
    assert_includes File.read(File.expand_path("../config/routes.rb", __dir__)), "resources :digests, only: :show"
    assert_includes File.read(File.expand_path(
      "../app/controllers/recording_studio_notifications/notifications_controller.rb", __dir__
    )), "where.missing(:digest_item)"
  end

  def test_commentable_hook_wires_notification
    initializer = File.read(File.expand_path("../test/dummy/config/initializers/recording_studio_commentable.rb",
                                             __dir__))
    model = File.read(File.expand_path("../test/dummy/app/models/page.rb", __dir__))

    assert_includes model, "include RecordingStudioCommentable::Commentable"
    assert_includes initializer, "RecordingStudioCommentable.configuration.hooks.after_service"
    assert_includes initializer, "RecordingStudioCommentable::Services::CreateComment"
    assert_includes initializer, "RecordingStudioNotifications.notify"
    assert_includes initializer, "notification_type: :page_comment"
    assert_includes initializer, "page_path(page_recordable)"
  end

  def test_pages_routes_and_views_use_flatpack
    routes = File.read(File.expand_path("../test/dummy/config/routes.rb", __dir__))
    controller = File.read(File.expand_path("../test/dummy/app/controllers/pages_controller.rb", __dir__))
    index_view = File.read(File.expand_path("../test/dummy/app/views/pages/index.html.erb", __dir__))
    show_view = File.read(File.expand_path("../test/dummy/app/views/pages/show.html.erb", __dir__))

    assert_includes routes, "mount RecordingStudioCommentable::Engine"
    assert_includes routes, "resources :pages"
    assert_includes controller, "notify_workspace_users_page_created!"
    assert_includes controller, "notification_type: :page_created"
    assert_includes controller, "next if recipient == current_user"
    assert_includes index_view, "FlatPack::Table::Component"
    assert_includes index_view, '"Add Page"'
    assert_includes show_view, "FlatPack::PageTitle::Component"
    assert_includes show_view, "FlatPack::Card::Component"
    refute_includes index_view, "<style"
    refute_includes show_view, "<style"
  end
end
