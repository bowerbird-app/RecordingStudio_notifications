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

  def test_engine_ships_only_english_locale_files
    files = Dir[File.join(engine_locales_dir, "*")].map { |path| File.basename(path) }

    assert_equal ["en.yml"], files.sort
  end

  def test_rails_i18n_load_path_includes_the_gem_english_locale_file
    locale_path = File.join(engine_locales_dir, "en.yml")

    assert_includes I18n.load_path.map { |path| File.expand_path(path) }, File.expand_path(locale_path)
  end

  def test_dummy_french_covers_every_engine_english_key
    english = flatten_keys(locale_tree(File.join(engine_locales_dir, "en.yml"), "en"))
    french = flatten_keys(locale_tree(File.join(dummy_locales_dir, "fr.yml"), "fr"))
    missing = english - french

    assert_empty missing, "dummy fr.yml is missing keys present in engine en.yml: #{missing.join(', ')}"
  end

  def test_english_default_copy_is_unchanged
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
      assert_equal "Jul 3", Copy.compact_day(Date.new(2026, 7, 3))
      ADMIN_KEYS.each do |key, english|
        assert_equal english, Copy.t("admin.all_notifications.#{key}")
      end
      assert_equal "Type", Copy.t("admin.all_notifications.columns.type")
      assert_equal "Root", Copy.t("admin.all_notifications.scope.root")
      assert_equal "Unread", Copy.t("admin.all_notifications.status.unread")
    end
  end

  def test_english_keys_resolve_without_missing_translations
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

  private

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
