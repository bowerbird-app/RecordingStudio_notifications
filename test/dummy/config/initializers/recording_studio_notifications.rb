# frozen_string_literal: true

RecordingStudioNotifications.configure do |config|
  config.actor_resolver = -> { Current.actor }
  config.current_root_resolver = lambda do |controller:|
    controller.send(:current_root_recording) if controller.respond_to?(:current_root_recording, true)
  end

  config.notification_types.register(
    :page_comment,
    label: "Page comment",
    description: "A collaborator commented on a page.",
    default_channels: [:in_app],
    available_channels: [:in_app],
    scope: :optional_root
  )

  config.notification_types.register(
    :workspace_digest,
    label: "Workspace digest",
    description: "A summary of workspace activity.",
    default_channels: [:in_app],
    available_channels: [:in_app],
    scope: :optional_root
  )
end
