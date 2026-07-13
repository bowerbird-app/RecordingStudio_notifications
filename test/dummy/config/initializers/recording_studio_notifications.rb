# frozen_string_literal: true

RecordingStudioNotifications.configure do |config|
  # Optional overrides for host-app context resolution.
  # If omitted, the engine falls back to its default resolvers.
  config.actor_resolver = -> { Current.actor }
  config.current_root_resolver = lambda do |controller:|
    controller.send(:current_root_recording) if controller.respond_to?(:current_root_recording, true)
  end

  config.notification_types.register(
    :workspace_change,
    label: "Workspace change",
    category: :workspace,
    description: "Root-scoped notification for workspace-level updates.",
    icon: :bell,
    default_channels: [:in_app],
    available_channels: [:in_app],
    scope: :root
  )

  config.notification_types.register(
    :system_announcement,
    label: "System announcement",
    category: :system,
    description: "Global rootless notification sent to all recipients.",
    icon: :exclamation_triangle,
    default_channels: [],
    required_channels: [:in_app],
    available_channels: [:in_app],
    scope: :global
  )

  config.notification_types.register(
    :page_comment,
    label: "Page comment",
    category: :page,
    description: "Optional-root notification for comments on pages.",
    icon: :chat_bubble_left_ellipsis,
    default_channels: [:in_app],
    available_channels: [:in_app],
    scope: :optional_root
  )

  config.notification_types.register(
    :page_created,
    label: "Page created",
    category: :page,
    description: "Root-scoped notification when a new page is created.",
    icon: :document_text,
    default_channels: [:in_app],
    available_channels: [:in_app],
    scope: :root
  )

end