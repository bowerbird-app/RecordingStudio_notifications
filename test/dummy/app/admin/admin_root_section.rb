# frozen_string_literal: true

Object.send(:remove_const, :AdminRootSection) if defined?(AdminRootSection)

class AdminRootSection < RecordingStudioAdmin::Section
  key :root
  icon :shield
  title "Admin"
  subtitle "Admin dashboard"

  link :all_notifications,
       text: "All notifications",
       url: ->(context) { context.admin_screen_path("recording_studio_notifications_all_notifications") },
       style: :primary

  link :admin_activity_logs,
       text: "Activity logs",
       url: ->(context) { context.admin_section_path("admin_activity_logs") },
       style: :secondary
end

RecordingStudioAdmin.register_section(AdminRootSection)