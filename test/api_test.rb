# frozen_string_literal: true

require "test_helper"
require "recording_studio_api"

class ApiTest < Minitest::Test
  def test_register_is_a_noop_when_api_is_unavailable
    api = File.read(File.expand_path("../lib/recording_studio_notifications/api.rb", __dir__))

    assert_includes api, "return unless defined?(::RecordingStudioApi)"
    refute_includes api, "respond_to?(:register_endpoint"
    refute_includes api, "respond_to?(:registered_endpoint"
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
    query = File.read(File.expand_path("../lib/recording_studio_notifications/api/query.rb", __dir__))

    assert_includes engine, 'initializer "recording_studio_notifications.api"'
    assert_includes engine, "RecordingStudioNotifications::Api.register!"
    assert_includes api, "RecordingStudioApi.register_endpoint"
    assert_includes api, "RecordingStudioApi.configuration.each_api"
    assert_includes api, "return unless defined?(::RecordingStudioApi)"
    assert_includes api, "notifications.inbox"
    assert_includes api, "notifications.show"
    assert_includes api, "notifications.mark_read"
    assert_includes api, "notifications.mark_unread"
    assert_includes api, "notifications.archive"
    assert_includes api, "notifications.unarchive"
    refute_includes api, "notifications.clear"
    assert_includes api, "notifications.preferences"
    assert_includes api, "notifications.update_preferences"
    refute_includes api, "register_capability_action"
    refute_includes api, "required_role"
    refute File.exist?(File.expand_path("../lib/recording_studio_notifications/mcp.rb", __dir__))
    assert_includes inbox, "Notification.for_recipient"
    assert_includes inbox, ".active.visible_in_inbox.in_inbox"
    assert_includes inbox, "visible_notification?"
    assert_includes inbox, "title: TITLE"
    assert_includes gate, "grant.authorize!"
    assert_includes gate, "NotificationAuthorization.allowed?"
    assert_includes gate, "notification.inbox?"
    assert_includes gate, "RequestPayload.call"
    refute_includes gate, "to_unsafe_h"
    assert_includes member, "mark_read!"
    assert_includes member, "mark_unread!"
    assert_includes member, "archive!"
    assert_includes member, "unarchive!"
    refute_includes member, "clear!"
    assert_includes prefs, "Preference.set!"
    assert_includes prefs, "Preference.set_cadence!"
    assert_includes prefs, "manage_preferences"
    refute_includes prefs, "to_unsafe_h"
    refute_includes prefs, 'attributes[:x] || attributes["x"]'
    refute_includes query, "def normalize_page"
    refute_includes gate, "Pundit"
    refute_includes inbox, "Pundit"
  end

  def test_registration_is_idempotent_and_covers_the_catalog
    registrations = []
    apis = [Struct.new(:name).new(:public), Struct.new(:name).new(:operations)]
    RecordingStudioApi.stub(:registered_endpoint, lambda { |name, api: :public, **|
      registrations.find { |entry| entry.fetch(:name) == name && entry[:api] == api }
    }) do
      RecordingStudioApi.stub(:register_endpoint, lambda { |name, api: :public, **options|
        registrations << { name: name, api: api, **options }
      }) do
        RecordingStudioApi.configuration.stub(:each_api, lambda { |&block|
          apis.each { |api| block.call(api) }
        }) do
          2.times { RecordingStudioNotifications::Api.register! }
        end
      end
    end

    names = registrations.map { |entry| [entry.fetch(:api), entry.fetch(:name)] }
    expected = apis.flat_map do |api|
      RecordingStudioNotifications::Api::ENDPOINTS.map { |endpoint| [api.name, endpoint.fetch(:name)] }
    end
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
