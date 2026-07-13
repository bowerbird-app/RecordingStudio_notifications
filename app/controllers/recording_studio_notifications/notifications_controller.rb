# frozen_string_literal: true

require "recording_studio_notifications/services/inbox_grouping"

module RecordingStudioNotifications
  class NotificationsController < ApplicationController
    PER_PAGE = 25

    layout "recording_studio_notifications/blank", only: :index

    before_action :set_recipient
    before_action :set_notification, only: %i[show open mark_read mark_unread archive unarchive]

    def index
      return unless authorize_notifications!(recipient: @recipient)

      @inbox_scope = notifications_inbox_scope
      @current_root_recording = current_notifications_root_recording
      @page = current_page
      @notification_sections, @has_next_page = visible_notification_sections_page(scoped_notifications)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def menu
      return unless authorize_notifications!(recipient: @recipient)

      # Menu polling should not depend on current-root query params from the host page.
      # Show a recent feed across all accessible notifications for the actor.
      @inbox_scope = "all"
      @current_root_recording = current_notifications_root_recording

      visible = visible_notifications(scoped_notifications)
      limit = normalized_menu_limit
      recent_groups = grouped_notification_sections(visible).flat_map(&:groups)
        .sort_by { |group| [group.latest_notification.created_at, group.id] }
        .reverse
        .first(limit)
      payload = recent_groups.map { |group| menu_group_payload(group) }
      unread_count = visible.count(&:unread?)

      render json: {
        unread_count: unread_count,
        notifications: payload,
        polling_interval_seconds: RecordingStudioNotifications.configuration.polling_interval_seconds,
        menu_html: render_to_string(
          partial: "recording_studio_notifications/notifications/menu_component",
          formats: [:html],
          locals: {
            unread_count: unread_count,
            notifications: payload,
            see_all_href: notifications_path
          }
        )
      }
    end

    def show
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
      return if visible_notification?(@notification)

      head :forbidden
    end

    def open
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
      return head :forbidden unless visible_notification?(@notification)

      @notification.mark_read! if @notification.unread?

      destination = @notification.url.presence || notification_path(@notification)
      redirect_to destination, allow_other_host: true
    end

    def mark_read
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
      return head :forbidden unless visible_notification?(@notification)

      @notification.mark_read!
      redirect_back fallback_location: notification_path(@notification), notice: "Notification marked read."
    end

    def mark_unread
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
      return head :forbidden unless visible_notification?(@notification)

      @notification.mark_unread!
      redirect_back fallback_location: notification_path(@notification), notice: "Notification marked unread."
    end

    def mark_group_read
      return unless authorize_notifications!(recipient: @recipient)

      @inbox_scope = notifications_inbox_scope
      @current_root_recording = current_notifications_root_recording
      group = visible_notification_group(params[:group_id])
      return head :not_found unless group

      Notification.transaction do
        group.notifications.select(&:unread?).each { |notification| notification.mark_read! }
      end

      redirect_back fallback_location: notifications_path, notice: "Notification group marked read."
    end

    def archive
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
      return head :forbidden unless visible_notification?(@notification)

      @notification.archive!
      redirect_back fallback_location: notification_path(@notification), notice: "Notification archived."
    end

    def unarchive
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
      return head :forbidden unless visible_notification?(@notification)

      @notification.unarchive!
      redirect_back fallback_location: notification_path(@notification), notice: "Notification unarchived."
    end

    private

    def set_recipient
      @recipient = current_notifications_actor
      head :unauthorized unless @recipient
    end

    def set_notification
      @notification = Notification.for_recipient(@recipient).find(params[:id])
    end

    def scoped_notifications
      notifications = Notification.for_recipient(@recipient).active
      notifications = notifications.for_current_root_inbox(@current_root_recording) if @inbox_scope == "current_root"
      notifications.newest_first
    end

    def visible_notifications(notifications)
      notifications.select { |notification| visible_notification?(notification) }
    end

    def visible_notification_sections_page(notifications_scope)
      all_sections = grouped_notification_sections(visible_notifications(notifications_scope))
      groups = all_sections.flat_map(&:groups)
      page_groups = groups.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
      sections = page_groups.group_by(&:notification_type).map do |type, section_groups|
        original_section = all_sections.find { |section| section.notification_type == type }
        Services::InboxGrouping::Section.new(
          notification_type: type,
          label: original_section.label,
          groups: section_groups
        )
      end

      [sections, groups.size > @page * PER_PAGE]
    end

    def visible_notification?(notification)
      Services::NotificationAuthorization.visible_notification?(
        actor: current_notifications_actor,
        notification: notification,
        controller: self
      )
    end

    # Keep notification list filtering separate from root-switch scope selection.
    def notifications_inbox_scope
      "current_root"
    end

    def normalized_menu_limit
      requested_limit = params[:limit].to_i
      return 5 if requested_limit <= 0

      [requested_limit, 25].min
    end

    def current_page
      page = params[:page].to_i
      page.positive? ? page : 1
    end

    def menu_notification_payload(notification)
      MenuPayload.serialize(
        notification: notification,
        href: open_notification_path(notification)
      )
    end

    def menu_group_payload(group)
      return menu_notification_payload(group.latest_notification) if group.individual?

      MenuPayload.serialize_group(group: group, href: notifications_path(anchor: group.id))
    end

    def grouped_notification_sections(notifications)
      Services::InboxGrouping.new(recipient: @recipient, notifications: notifications).call
    end

    def visible_notification_group(group_id)
      return if group_id.blank?

      visible = visible_notifications(scoped_notifications)
      grouped_notification_sections(visible).flat_map(&:groups).find { |group| group.id == group_id }
    end

    # Override root-switch scope extraction so `scope=current_root` in the
    # notifications inbox filter cannot suppress the top-nav root dropdown.
    def recording_studio_root_switchable_scope_key
      params[:root_scope].presence || params[:scope_key].presence
    end
  end
end
