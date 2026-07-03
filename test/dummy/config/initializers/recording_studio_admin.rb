# frozen_string_literal: true

RecordingStudioAdmin.configure do |config|
  config.default_mount_path = "/admin"
  config.engine_layout = "admin"
  config.authentication_method = :authenticate_user!
  config.current_actor_method = :current_user

  # Progressive widget loading keeps the page shell fast and lets widgets load
  # through engine-owned endpoints with bounded browser concurrency. It is on by
  # default; uncomment the next line only if you need synchronous widget renders.
  # config.async_widgets.enabled = false
  # config.async_widgets.max_concurrent_requests = 4
  # config.async_widgets.retry_count = 1

  config.access_recording_resolver = lambda do |context|
    # Return the AdminRoot recording for the current admin surface.
    # In this dummy app the admin root is the first AdminRoot recordable.
    root_recordable = AdminRoot.first
    next nil unless root_recordable

    RecordingStudio.root_recording_for(root_recordable)
  end

  # Add per-route admin surfaces when different URL entrypoints should resolve
  # different access recordings or layouts.
  # config.surface :stats do |surface|
  #   surface.access_recording_resolver = ->(context) { context.controller.current_user_recording }
  #   surface.root_section :page_views
  # end
end

# Keep admin definitions in app/admin capability folders, then register them from
# config.to_prepare blocks so Rails reloads safely.
# If your app/admin files are manifest-loaded instead of Zeitwerk-named, add
# `Rails.autoloaders.main.ignore(root.join("app/admin"))` in config/application.rb.
Rails.application.config.to_prepare do
  Dir[Rails.root.join("app/admin/**/*.rb")].sort.each { |f| load f }

  if defined?(RecordingStudioAdmin::ApplicationController) && defined?(ApplicationHelper)
    RecordingStudioAdmin::ApplicationController.helper(ApplicationHelper)
  end
end
