# frozen_string_literal: true

require "test_helper"
require "action_controller"

class NotificationUrlTest < Minitest::Test
  NotificationRef = Struct.new(:to_param)

  def setup
    draw_notification_routes
    install_application_hook
  end

  def teardown
    return unless Rails.instance_variable_defined?(:@notification_url_application_for_test)

    Rails.remove_instance_variable(:@notification_url_application_for_test)
  end

  def test_notification_url_is_absolute_and_uses_mailer_host_options
    install_application(routes: { host: "routes.example", protocol: "http" },
                        mailer: { host: "mail.example", protocol: "https" })

    url = RecordingStudioNotifications.notification_url(NotificationRef.new("notice-1"))

    assert_equal "https://mail.example/notifications/notice-1/open", url
  end

  def test_notification_url_uses_route_options_when_mailer_options_are_empty
    install_application(routes: { host: "routes.example", protocol: "https", port: 444 },
                        mailer: {})

    url = RecordingStudioNotifications.notification_url(NotificationRef.new("notice-2"))

    assert_equal "https://routes.example:444/notifications/notice-2/open", url
  end

  private

  def draw_notification_routes
    return if RecordingStudioNotifications::Engine.routes.named_routes.names.include?(:open_notification)

    load File.expand_path("../config/routes.rb", __dir__)
  end

  def install_application(routes:, mailer:)
    application = Object.new
    route_set = Object.new
    route_set.define_singleton_method(:default_url_options) { routes }
    mailer_config = Object.new
    mailer_config.define_singleton_method(:default_url_options) { mailer }
    config = Object.new
    config.define_singleton_method(:action_mailer) { mailer_config }
    application.define_singleton_method(:routes) { route_set }
    application.define_singleton_method(:config) { config }
    Rails.instance_variable_set(:@notification_url_application_for_test, application)
  end

  def install_application_hook
    return if Rails.singleton_class.ancestors.include?(ApplicationHook)

    Rails.singleton_class.prepend(ApplicationHook)
  end

  module ApplicationHook
    def application
      return instance_variable_get(:@notification_url_application_for_test) if instance_variable_defined?(:@notification_url_application_for_test)

      super
    end
  end
end
