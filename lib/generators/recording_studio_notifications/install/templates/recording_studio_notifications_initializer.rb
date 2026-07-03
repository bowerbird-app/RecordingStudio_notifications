# frozen_string_literal: true

RecordingStudioNotifications.configure do |config|
  # Resolve the current actor for API calls and engine controllers.
  # config.actor_resolver = -> { Current.actor }

  # Resolve the selected Recording Studio root for scope=current_root inbox filtering.
  # If your app uses RecordingStudio::RootSwitchable, include its ControllerSupport
  # in the host controller or resolve the selected root here.
  # config.current_root_resolver = ->(controller:) { controller.send(:current_root_recording) if controller.respond_to?(:current_root_recording, true) }

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
