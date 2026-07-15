module ApplicationHelper
	include RecordingStudioAccessible::AccessManagementHelper if defined?(RecordingStudioAccessible::AccessManagementHelper)
  include RecordingStudioNotifications::MenuHelper if defined?(RecordingStudioNotifications::MenuHelper)

	NOTIFICATION_ICON_BY_TYPE = {
		"page_comment" => :chat_bubble_left_ellipsis,
		"page_created" => :document_text,
		"mention" => :at_symbol,
		"approval_requested" => :check_circle,
		"approval_granted" => :check_circle,
		"approval_rejected" => :x_circle,
		"system_alert" => :exclamation_triangle
	}.freeze

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

	def demo_notification_path
		recording_studio_notifications.notifications_path
	end

	def demo_notifications(limit: 5)
		return [] unless user_signed_in?
		return [] unless limit.to_i.positive?

		[]
	rescue StandardError
		[]
	end

	# Renders the FlatPack notification menu introduced in flat_pack v0.1.112.
	def recording_studio_notifications_menu(limit: 5)
		return unless user_signed_in?
		return unless respond_to?(:recording_studio_notifications_async_menu)

		recording_studio_notifications_async_menu(recipient: current_user, limit: limit)
	rescue StandardError
		nil
	end
end
