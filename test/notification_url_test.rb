# frozen_string_literal: true

require "test_helper"
require "action_controller"

class NotificationUrlTest < Minitest::Test
  NotificationRef = Struct.new(:to_param)

  def setup
    draw_notification_routes
  end

  def test_notification_url_is_absolute_and_uses_mailer_host_options
    url = with_application(routes: { host: "routes.example", protocol: "http" },
                           mailer: { host: "mail.example", protocol: "https" }) do
      RecordingStudioNotifications.notification_url(NotificationRef.new("notice-1"))
    end

    assert_equal "https://mail.example/notifications/notice-1/open", url
    assert RecordingStudioNotifications::UrlSafety.safe?(url, allowed_hosts: ["mail.example"])
    refute RecordingStudioNotifications::UrlSafety.safe?(url, allowed_hosts: ["other.example"])
  end

  def test_notification_url_uses_route_options_when_mailer_options_are_empty
    url = with_application(routes: { host: "routes.example", protocol: "https", port: 444 },
                           mailer: {}) do
      RecordingStudioNotifications.notification_url(NotificationRef.new("notice-2"))
    end

    assert_equal "https://routes.example:444/notifications/notice-2/open", url
    assert RecordingStudioNotifications::UrlSafety.safe?(url, allowed_hosts: ["routes.example"])
  end

  def test_blank_mailer_host_does_not_override_the_route_host
    url = with_application(routes: { host: "routes.example", protocol: "https" },
                           mailer: { host: nil, protocol: "" }) do
      RecordingStudioNotifications.notification_url(NotificationRef.new("notice-4"))
    end

    assert_equal "https://routes.example/notifications/notice-4/open", url

    url = with_application(routes: { host: "routes.example", protocol: "https" },
                           mailer: { host: "" }) do
      RecordingStudioNotifications.notification_url(NotificationRef.new("notice-5"))
    end

    assert_equal "https://routes.example/notifications/notice-5/open", url
  end

  def test_notification_url_requires_a_host
    error = assert_raises(ArgumentError) do
      with_application(routes: {}, mailer: {}) do
        RecordingStudioNotifications.notification_url(NotificationRef.new("notice-3"))
      end
    end

    assert_equal "Set config.action_mailer.default_url_options[:host] so notification_url is absolute", error.message
  end

  private

  def draw_notification_routes
    return if RecordingStudioNotifications::Engine.routes.named_routes.names.include?(:open_notification)

    load File.expand_path("../config/routes.rb", __dir__)
  end

  def with_application(routes:, mailer:, &)
    Rails.stub(:application, application_for(routes: routes, mailer: mailer), &)
  end

  def application_for(routes:, mailer:)
    application = Object.new
    route_set = Object.new
    route_set.define_singleton_method(:default_url_options) { routes }
    mailer_config = Object.new
    mailer_config.define_singleton_method(:default_url_options) { mailer }
    config = Object.new
    config.define_singleton_method(:action_mailer) { mailer_config }
    application.define_singleton_method(:routes) { route_set }
    application.define_singleton_method(:config) { config }
    application
  end
end
