# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class HostLocaleOverrideTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  HOST_EMPTY = "Host says the inbox is empty"
  HOST_OVERRIDE_LOCALE = Rails.root.join("test/locales/host_override.en.yml").freeze

  setup do
    @user = User.find_or_create_by!(email: "host-override@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    sign_in @user
  end

  test "host locale override wins over gem English on a real notifications page" do
    assert_path_exists HOST_OVERRIDE_LOCALE
    refute_includes HOST_OVERRIDE_LOCALE.to_s, "config/locales",
                    "override must stay test-only so the default dummy UI keeps gem English"

    with_restored_i18n_backend do
      I18n.load_path << HOST_OVERRIDE_LOCALE.to_s
      I18n.backend.load_translations(HOST_OVERRIDE_LOCALE.to_s)

      get "/notifications"

      assert_response :success
      assert_includes response.body, HOST_EMPTY
      refute_includes response.body, "No notifications yet."
      assert_equal HOST_EMPTY, I18n.t("recording_studio.notifications.inbox.empty")
    end
  end

  test "default dummy UI still shows gem English when no test override is loaded" do
    get "/notifications"

    assert_response :success
    assert_includes response.body, "No notifications yet."
    refute_includes response.body, HOST_EMPTY
  end

  private

  # Snapshot load path + Simple backend translations, then restore without a bare
  # I18n.reload! so any store_translations from other tests stay intact.
  def with_restored_i18n_backend
    previous_load_path = I18n.load_path.dup
    previous_translations = i18n_backend_translations_snapshot
    yield
  ensure
    I18n.load_path.replace(previous_load_path)
    restore_i18n_backend_translations(previous_translations) if previous_translations
  end

  def i18n_backend_translations_snapshot
    backend = I18n.backend
    backend.send(:init_translations) unless backend.initialized?
    translations =
      if backend.respond_to?(:translations)
        backend.translations
      else
        backend.instance_variable_get(:@translations)
      end
    return unless translations

    deep_plain_copy(translations)
  end

  def restore_i18n_backend_translations(snapshot)
    backend = I18n.backend
    backend.instance_variable_set(:@translations, snapshot)
    backend.instance_variable_set(:@initialized, true) if backend.instance_variable_defined?(:@initialized)
  end

  def deep_plain_copy(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, nested), copy| copy[key] = deep_plain_copy(nested) }
    when Array
      value.map { |nested| deep_plain_copy(nested) }
    else
      value
    end
  end
end
