# frozen_string_literal: true

module RecordingStudioNotifications
  class NotificationsController < ApplicationController
    before_action :set_recipient
    before_action :set_notification, only: %i[show open mark_read mark_unread archive]

    def index
      return unless authorize_notifications!(recipient: @recipient)

      @inbox_scope = notifications_inbox_scope
      @current_root_recording = current_notifications_root_recording
      @notifications = visible_notifications(scoped_notifications.limit(100))
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

    def archive
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
      return head :forbidden unless visible_notification?(@notification)

      @notification.archive!
      redirect_to notifications_path, notice: "Notification archived."
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

    def visible_notification?(notification)
      Services::NotificationAuthorization.visible_notification?(
        actor: current_notifications_actor,
        notification: notification,
        controller: self
      )
    end

    # Keep notification list filtering separate from root-switch scope selection.
    def notifications_inbox_scope
      params[:inbox_scope].presence_in(%w[all current_root]) ||
        params[:scope].presence_in(%w[all current_root]) ||
        "all"
    end

    # Override root-switch scope extraction so `scope=current_root` in the
    # notifications inbox filter cannot suppress the top-nav root dropdown.
    def recording_studio_root_switchable_scope_key
      params[:root_scope].presence || params[:scope_key].presence
    end
  end
end
