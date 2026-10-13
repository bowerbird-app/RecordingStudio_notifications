# frozen_string_literal: true

require "test_helper"
require "yaml"

class LocalesTest < Minitest::Test
  Copy = RecordingStudioNotifications::Copy

  ADMIN_KEYS = {
    "title" => "All notifications",
    "subtitle" => "Root-scoped and global notification overview",
    "summary" => "Notifications",
    "open_table" => "Open notifications table"
  }.freeze

  ERROR_KEYS = {
    "errors.notification.type_not_registered" => "is not registered",
    "errors.notification.root_required" => "is required",
    "errors.notification.root_must_be_blank" => "must be blank for global notifications",
    "errors.notification.root_must_match" => "must match recording and notifiable root",
    "errors.notification.url_not_safe" => "is not safe",
    "errors.preference.type_not_registered" => "is not registered",
    "errors.preference.channel_not_optional" => "must be an available optional channel",
    "errors.preference.invalid_shape" => "must be either a channel preference or a cadence override",
    "errors.preference.cadence_not_allowed" => "is not allowed for this notification type",
    "errors.delivery.channel_not_registered" => "is not registered",
    "inbox.overflow" => "9+"
  }.freeze

  def test_engine_ships_only_english_locale_files
    files = Dir[File.join(engine_locales_dir, "*")].map { |path| File.basename(path) }

    assert_equal ["en.yml"], files.sort
  end

  def test_rails_i18n_load_path_includes_the_gem_english_locale_file
    # with_gem_english_locale_only puts only en.yml on the path and reloads.
    # Assert that file actually drives lookups (not merely that the path we set is present).
    with_gem_english_locale_only do
      locale_path = File.expand_path(File.join(engine_locales_dir, "en.yml"))
      assert_equal([locale_path], I18n.load_path.map { |path| File.expand_path(path) })
      assert_equal "Notifications", I18n.t("recording_studio.notifications.inbox.title")
      assert_equal "Notification marked read.", I18n.t("recording_studio.notifications.flashes.marked_read")
    end
  end

  def test_lib_sources_do_not_append_i18n_load_path
    lib_dir = File.expand_path("../lib", __dir__)
    ruby_files = Dir[File.join(lib_dir, "**", "*.rb")]

    refute_empty ruby_files, "expected lib/**/*.rb files to scan"

    ruby_files.each do |path|
      source = File.read(path)

      refute_includes source, "i18n.load_path", "#{path} must not touch i18n.load_path"
      refute_includes source, "I18n.load_path", "#{path} must not touch I18n.load_path"
    end
  end

  def test_dummy_french_covers_every_engine_english_key
    english = flatten_keys(locale_tree(File.join(engine_locales_dir, "en.yml"), "en"))
    french = flatten_keys(locale_tree(File.join(dummy_locales_dir, "fr.yml"), "fr"))
    missing = english - french

    assert_empty missing, "dummy fr.yml is missing keys present in engine en.yml: #{missing.join(', ')}"
  end

  def test_english_default_copy_is_unchanged
    with_gem_english_locale_only do
      I18n.with_locale(:en) do
        assert_equal "Notifications", Copy.t("inbox.title")
        assert_equal "Clear all", Copy.t("inbox.clear_all")
        assert_equal "Settings", Copy.t("inbox.settings")
        assert_equal "No notifications yet.", Copy.t("inbox.empty")
        assert_equal "Notification settings", Copy.t("settings.title")
        assert_equal "Save settings", Copy.t("settings.save")
        assert_equal "Notification marked read.", Copy.t("flashes.marked_read")
        assert_equal "Notification preferences updated.", Copy.t("flashes.preferences_updated")
        assert_equal "This channel can't be removed", Copy.t("settings.required_channel_tooltip")
        assert_equal "9+", Copy.t("inbox.overflow")
        ADMIN_KEYS.each do |key, english|
          assert_equal english, Copy.t("admin.all_notifications.#{key}")
        end
        assert_equal "Type", Copy.t("admin.all_notifications.columns.type")
        assert_equal "Root", Copy.t("admin.all_notifications.scope.root")
        assert_equal "Unread", Copy.t("admin.all_notifications.status.unread")
        ERROR_KEYS.each do |key, english|
          assert_equal english, Copy.t(key)
        end
      end
    end

    I18n.with_locale(:en) do
      assert_equal "Jul 3", Copy.compact_day(Date.new(2026, 7, 3))
    end
  end

  def test_english_keys_resolve_without_missing_translations
    with_gem_english_locale_only do
      I18n.with_locale(:en) do
        flatten_keys(locale_tree(File.join(engine_locales_dir, "en.yml"), "en")).each do |key|
          full_key = "recording_studio.notifications.#{key}"
          translation = I18n.t(full_key, default: nil)

          refute_nil translation, "#{full_key} should resolve"
          assert_equal translation, I18n.t(full_key, raise: true)
          refute_match(/translation missing/i, translation.to_s)
        end
      end
    end
  end

  def test_en_yml_nests_admin_keys_under_recording_studio_notifications
    tree = locale_tree(File.join(engine_locales_dir, "en.yml"), "en")
           .fetch("admin")
           .fetch("all_notifications")

    ADMIN_KEYS.each do |key, english|
      assert_equal english, tree.fetch(key)
    end
  end

  def test_component_text_overrides_win_including_nil
    assert_equal "Notifications", Copy.value(Copy::UNSET, "menu.title")
    assert_equal "Acme alerts", Copy.value("Acme alerts", "menu.title")
    assert_nil Copy.value(nil, "menu.title")
  end

  def test_host_translation_overrides_english
    # Init translations before store: reload! leaves the backend cold, and the
    # next lookup would reload YAML over an early store_translations.
    Copy.t("menu.title")

    I18n.backend.store_translations(:en, acme_title)
    assert_equal "Acme alerts", Copy.t("menu.title")
  ensure
    I18n.backend.store_translations(:en, default_title)
  end

  def test_yes_no_on_off_yaml_keys_resolve_without_default
    # Psych loads bare yes/no/on/off as booleans; quoted keys must resolve.
    with_gem_english_locale_only do
      I18n.with_locale(:en) do
        tree = locale_tree(File.join(engine_locales_dir, "en.yml"), "en")
        booleanish = flatten_keys(tree).select do |key|
          key.split(".").any? { |segment| %w[yes no on off true false null].include?(segment.downcase) }
        end

        booleanish.each do |key|
          assert_equal I18n.t("recording_studio.notifications.#{key}", raise: true),
                       Copy.t(key)
        end
      end
    end
  end

  private

  def with_gem_english_locale_only
    previous = I18n.load_path.dup
    I18n.load_path = [File.join(engine_locales_dir, "en.yml")]
    I18n.backend.load_translations
    yield
  ensure
    I18n.load_path = previous
    I18n.backend.load_translations
    I18n.backend.store_translations(:en, gem_english_tree)
  end

  def gem_english_tree
    YAML.safe_load_file(File.join(engine_locales_dir, "en.yml"), aliases: true).fetch("en")
  end

  def engine_locales_dir
    File.expand_path("../config/locales", __dir__)
  end

  def dummy_locales_dir
    File.expand_path("dummy/config/locales", __dir__)
  end

  def locale_tree(path, locale)
    yaml = YAML.safe_load_file(path, aliases: true)
    yaml.fetch(locale).fetch("recording_studio").fetch("notifications")
  end

  def flatten_keys(hash, prefix = [])
    hash.flat_map do |key, value|
      path = prefix + [key.to_s]
      value.is_a?(Hash) ? flatten_keys(value, path) : [path.join(".")]
    end
  end

  def acme_title
    { recording_studio: { notifications: { menu: { title: "Acme alerts" } } } }
  end

  def default_title
    { recording_studio: { notifications: { menu: { title: "Notifications" } } } }
  end
end
