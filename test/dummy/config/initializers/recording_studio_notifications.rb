# frozen_string_literal: true

RecordingStudioNotifications.configure do |config|
  config.actor_resolver = -> { Current.actor }

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
