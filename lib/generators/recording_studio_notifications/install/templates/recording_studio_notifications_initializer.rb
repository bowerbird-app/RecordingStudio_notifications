# frozen_string_literal: true

RecordingStudioNotifications.configure do |config|
  # Resolve the current actor for API calls and engine controllers.
  # config.actor_resolver = -> { Current.actor }

  # Relative paths are always allowed. Add trusted hosts for absolute http(s) URLs.
  # config.allowed_url_hosts = [Rails.application.routes.default_url_options[:host]].compact

  # Register notification types used by your app.
  config.notification_types.register(
    :generic,
    label: "Generic notification",
    description: "Default in-app notification",
    default_channels: [:in_app],
    available_channels: [:in_app],
    scope: :optional_root
  )

  # Register custom channels here. The bundled :in_app channel is enabled by default.
  # config.channels.register(:custom, MyNotificationAdapter.new)
end
