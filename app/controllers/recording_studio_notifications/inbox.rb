# frozen_string_literal: true

module RecordingStudioNotifications
  module Inbox
    private

    def scoped_notifications
      notifications = Notification.for_recipient(@recipient).active.visible_in_inbox.in_inbox
      notifications = notifications.for_current_root_inbox(@current_root_recording) if @inbox_scope == "current_root"
      notifications.newest_first
    end

    def prepare_inbox
      @inbox_scope = notifications_inbox_scope
      @current_root_recording = current_notifications_root_recording
      @page = current_page
      @visible_notifications = visible_notifications(scoped_notifications)
      @has_unread_notifications = @visible_notifications.any?(&:unread?)
      @notification_sections, @has_next_page = visible_notification_sections_page(@visible_notifications)
    end

    def visible_notifications(notifications)
      notifications.select { |notification| visible_notification?(notification) }
    end

    def visible_notification_sections_page(notifications_scope)
      all_sections = grouped_notification_sections(visible_notifications(notifications_scope))
      groups = all_sections.flat_map(&:groups)
      page_groups = groups.slice((@page - 1) * NotificationsController::PER_PAGE, NotificationsController::PER_PAGE) || []
      sections = page_groups.group_by(&:notification_type).map do |type, section_groups|
        original_section = all_sections.find { |section| section.notification_type == type }
        Services::InboxGrouping::Section.new(
          notification_type: type,
          label: original_section.label,
          groups: section_groups
        )
      end

      [sections, groups.size > @page * NotificationsController::PER_PAGE]
    end

    def visible_notification?(notification)
      Services::NotificationAuthorization.visible_notification?(
        actor: current_notifications_actor,
        notification: notification,
        controller: self
      )
    end

    def notifications_inbox_scope
      "current_root"
    end

    def current_page
      page = params[:page].to_i
      page.positive? ? page : 1
    end

    def current_group_page
      page = params[:page].to_i
      page.positive? ? page : 1
    end

    def grouped_notification_sections(notifications)
      Services::InboxGrouping.new(recipient: @recipient, notifications: notifications).call
    end

    def visible_notification_group(group_id)
      return if group_id.blank?

      visible = visible_notifications(scoped_notifications)
      grouped_notification_sections(visible).flat_map(&:groups).find { |group| group.id == group_id }
    end
  end
end
