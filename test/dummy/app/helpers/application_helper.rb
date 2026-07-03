module ApplicationHelper
	include RecordingStudioAccessible::AccessManagementHelper if defined?(RecordingStudioAccessible::AccessManagementHelper)

	# Host-provided helper consumed by RecordingStudioAdmin page shells.
	# Renders a lightweight access-management entry point for the current recording.
	def recording_studio_accessible_avatars(recording, button_style: :ghost, button_size: :md)
		return if recording.blank?
		return unless respond_to?(:recording_studio_accessible)

		access_count = RecordingStudio::Recording.unscoped
			.where(parent_recording_id: recording.id, recordable_type: "RecordingStudio::Access", trashed_at: nil)
			.count

		label = access_count.positive? ? "Access (#{access_count})" : "Manage access"

		render FlatPack::Button::Component.new(
			text: label,
			url: recording_studio_accessible.recording_accesses_path(recording),
			style: button_style,
			size: button_size
		)
	rescue StandardError
		nil
	end
end
