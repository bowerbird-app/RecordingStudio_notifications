# frozen_string_literal: true

require "recording_studio_notifications/services/inbox_grouping"

module RecordingStudioNotifications
  class NotificationsController < ApplicationController
    include Inbox
    include MenuJson

    PER_PAGE = 25
    GROUP_NOTIFICATIONS_PER_PAGE = 20

    before_action :set_recipient
    before_action :set_notification, only: %i[show open mark_read mark_unread archive unarchive]
    before_action :require_inbox_notification, only: %i[show mark_read mark_unread archive unarchive]

    def index
      return unless authorize_notifications!(recipient: @recipient)

      prepare_inbox

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def menu
      return unless authorize_notifications!(recipient: @recipient)

      # Keep menu results aligned with inbox filtering: current root + rootless.
      @inbox_scope = notifications_inbox_scope
      @current_root_recording = current_notifications_root_recording

      render json: menu_json
    end

    def group_page
      return unless authorize_notifications!(recipient: @recipient)

      @inbox_scope = notifications_inbox_scope
      @current_root_recording = current_notifications_root_recording
      @group = visible_notification_group(params[:group_id])
      return head :not_found unless @group

      @group_page = current_group_page
      offset = (@group_page - 1) * GROUP_NOTIFICATIONS_PER_PAGE
      @group_notifications = @group.notifications.slice(offset, GROUP_NOTIFICATIONS_PER_PAGE) || []
      @has_next_group_page = @group.notifications.size > offset + @group_notifications.size

      respond_to do |format|
        format.html
        format.turbo_stream { head :not_acceptable }
      end
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
      redirect_back fallback_location: notification_path(@notification),
                    notice: Copy.t("flashes.marked_read", default: "Notification marked read.")
    end

    def mark_unread
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
      return head :forbidden unless visible_notification?(@notification)

      @notification.mark_unread!
      redirect_back fallback_location: notification_path(@notification),
                    notice: Copy.t("flashes.marked_unread", default: "Notification marked unread.")
    end

    def clear_all
      return unless authorize_notifications!(recipient: @recipient)

      prepare_inbox

      Notification.transaction do
        @visible_notifications.select(&:unread?).each(&:clear!)
      end

      respond_to do |format|
        format.html do
          redirect_back fallback_location: notifications_path,
                        notice: Copy.t("flashes.cleared", default: "Unread notifications cleared."),
                        status: :see_other
        end
        format.turbo_stream do
          prepare_inbox
        end
      end
    end

    def archive
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
      return head :forbidden unless visible_notification?(@notification)

      @notification.archive!
      redirect_back fallback_location: notification_path(@notification),
                    notice: Copy.t("flashes.archived", default: "Notification archived.")
    end

    def unarchive
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
      return head :forbidden unless visible_notification?(@notification)

      @notification.unarchive!
      redirect_back fallback_location: notification_path(@notification),
                    notice: Copy.t("flashes.unarchived", default: "Notification unarchived.")
    end

    private

    def set_recipient
      @recipient = current_notifications_actor
      head :unauthorized unless @recipient
    end

    def set_notification
      @notification = Notification.for_recipient(@recipient).find(params[:id])
    end

    def require_inbox_notification
      head :not_found unless @notification.inbox?
    end

    def notification_group_dom_id(group)
      "#{group.id}-container"
    end

    # Override root-switch scope extraction so `scope=current_root` in the
    # notifications inbox filter cannot suppress the top-nav root dropdown.
    def recording_studio_root_switchable_scope_key
      params[:root_scope].presence || params[:scope_key].presence
    end
  end
end
