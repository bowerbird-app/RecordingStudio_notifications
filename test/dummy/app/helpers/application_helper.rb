module ApplicationHelper
	include RecordingStudioAccessible::AccessManagementHelper if defined?(RecordingStudioAccessible::AccessManagementHelper)

	NOTIFICATION_ICON_BY_TYPE = {
		"page_comment" => :chat_bubble_left_ellipsis,
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
		return [] unless defined?(RecordingStudioNotifications::Notification)

		recent_visible_notifications(limit: limit).map { |notification| notification_payload(notification) }
	rescue StandardError
		[]
	end

	# Renders the FlatPack notification menu introduced in flat_pack v0.1.112.
	def recording_studio_notifications_menu(limit: 5)
		return unless user_signed_in?
		return unless defined?(RecordingStudioNotifications::Notification)

		notifications = demo_notifications(limit: limit)
		unread_count = unread_visible_notifications_count

		return fallback_notifications_button(unread_count: unread_count) unless defined?(FlatPack::Notification::Component)

		render FlatPack::Notification::Component.new(
			unread_count: unread_count,
			see_all_href: demo_notification_path,
			notifications: notifications
		)
	rescue StandardError
		nil
	end

	private

	def recent_visible_notifications(limit:)
		all_visible_notifications.first(limit)
	end

	def unread_visible_notifications_count
		all_visible_notifications.count(&:unread?)
	end

	def all_visible_notifications
		@all_visible_notifications ||= begin
			notifications = RecordingStudioNotifications::Notification
				.for_recipient(current_user)
				.active
				.newest_first

			notifications.select do |notification|
				RecordingStudioNotifications::Services::NotificationAuthorization.visible_notification?(
					actor: current_user,
					notification: notification,
					controller: controller
				)
			end
		end
	end

	def notification_payload(notification)
		{
			title: notification.title,
			body: notification.body,
			href: recording_studio_notifications.open_notification_path(notification),
			unread: notification.unread?,
			time: notification.created_at,
			icon: notification_icon_for(notification)
		}
	end

	def notification_icon_for(notification)
		NOTIFICATION_ICON_BY_TYPE[notification.notification_type.to_s] || :bell
	end

	def fallback_notifications_button(unread_count:)
		label = unread_count.positive? ? "Notifications (#{unread_count})" : "Notifications"

		render FlatPack::Button::Component.new(
			text: label,
			url: demo_notification_path,
			style: :ghost,
			size: :md,
			icon: :bell
		)
	end
end
