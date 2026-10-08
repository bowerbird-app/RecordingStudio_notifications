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
			href: recording_studio_accessible.recording_accesses_path(recording),
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

	def dummy_language_selector
		return unless respond_to?(:recording_studio_language_selector)

		recording_studio_language_selector(
			class: "dummy-language-selector flex shrink-0 items-center gap-1.5 [&_label]:sr-only [&_button]:sr-only [&_.flat-pack-input-wrapper]:mb-0 [&_.flat-pack-select]:min-h-8 [&_.flat-pack-select]:min-w-28 [&_.flat-pack-select]:py-1 [&_.flat-pack-select]:text-sm",
			data: {
				turbo: false,
				controller: "dummy-language-selector",
				action: "change->dummy-language-selector#submit"
			}
		)
	end

	def dummy_document_attributes
		attributes = { "data-theme" => "rounded" }
		attributes.merge!(recording_studio_locale_attributes) if respond_to?(:recording_studio_locale_attributes)
		if respond_to?(:flat_pack_copy_data)
			attributes[:data] = (attributes[:data] || {}).merge(flat_pack_copy_data)
		end
		attributes
	end
end
