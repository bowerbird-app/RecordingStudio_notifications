# frozen_string_literal: true

require "test_helper"
require "recording_studio_api"

class ApiTest < Minitest::Test
  def test_register_is_a_noop_when_api_is_unavailable
    RecordingStudioNotifications::Api.stub(:available?, false) do
      assert_nil RecordingStudioNotifications::Api.register!
    end
  end

  def test_gemspec_omits_runtime_recording_studio_api_dependency
    gemspec = File.read(File.expand_path("../recording_studio_notifications.gemspec", __dir__))
    gemfile = File.read(File.expand_path("../Gemfile", __dir__))

    refute_includes gemspec, 'spec.add_dependency "recording_studio_api"'
    refute_includes gemspec, 'spec.add_development_dependency "recording_studio_api"'
    assert_includes gemfile, "recording_studio_api"
  end

  def test_engine_registers_api_when_present
    engine = File.read(File.expand_path("../lib/recording_studio_notifications/engine.rb", __dir__))
    api = File.read(File.expand_path("../lib/recording_studio_notifications/api.rb", __dir__))
    inbox = File.read(File.expand_path("../lib/recording_studio_notifications/api/inbox.rb", __dir__))
    gate = File.read(File.expand_path("../lib/recording_studio_notifications/api/gate.rb", __dir__))
    member = File.read(File.expand_path("../lib/recording_studio_notifications/api/member_action.rb", __dir__))
    prefs = File.read(File.expand_path("../lib/recording_studio_notifications/api/preferences.rb", __dir__))

    assert_includes engine, 'initializer "recording_studio_notifications.api"'
    assert_includes engine, "RecordingStudioNotifications::Api.register!"
    assert_includes api, "RecordingStudioApi.register_endpoint"
    assert_includes api, "return unless available?"
    assert_includes api, "notifications.inbox"
    assert_includes api, "notifications.show"
    assert_includes api, "notifications.mark_read"
    assert_includes api, "notifications.mark_unread"
    assert_includes api, "notifications.archive"
    assert_includes api, "notifications.unarchive"
    assert_includes api, "notifications.clear"
    assert_includes api, "notifications.preferences"
    assert_includes api, "notifications.update_preferences"
    refute_includes api, "register_capability_action"
    refute_includes api, "required_role"
    refute File.exist?(File.expand_path("../lib/recording_studio_notifications/mcp.rb", __dir__))
    assert_includes inbox, "Notification.for_recipient"
    assert_includes inbox, "visible_notification?"
    assert_includes inbox, "title: TITLE"
    assert_includes gate, "grant.authorize!"
    assert_includes gate, "NotificationAuthorization.allowed?"
    assert_includes member, "mark_read!"
    assert_includes member, "mark_unread!"
    assert_includes member, "archive!"
    assert_includes member, "unarchive!"
    assert_includes member, "clear!"
    assert_includes prefs, "Preference.set!"
    assert_includes prefs, "Preference.set_cadence!"
    assert_includes prefs, "manage_preferences"
    refute_includes gate, "Pundit"
    refute_includes inbox, "Pundit"
  end

  def test_registration_is_idempotent_and_covers_the_catalog
    registrations = []
    RecordingStudioApi.stub(:registered_endpoint, lambda { |name, **|
      registrations.find { |entry| entry.fetch(:name) == name }
    }) do
      RecordingStudioApi.stub(:register_endpoint, lambda { |name, **options|
        registrations << { name: name, **options }
      }) do
        2.times { RecordingStudioNotifications::Api.register! }
      end
    end

    names = registrations.map { |entry| entry.fetch(:name) }
    expected = RecordingStudioNotifications::Api::ENDPOINTS.map { |endpoint| endpoint.fetch(:name) }
    assert_equal expected, names

    registrations.each do |registration|
      openapi = registration.fetch(:openapi)
      assert openapi[:title]
      assert openapi[:summary]
      assert openapi[:description]
      assert_equal ["Notifications"], openapi[:tags]
    end
  end
end
