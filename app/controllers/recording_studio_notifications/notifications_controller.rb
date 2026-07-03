# frozen_string_literal: true

module RecordingStudioNotifications
  class NotificationsController < ApplicationController
    before_action :set_recipient
    before_action :set_notification, only: %i[show mark_read mark_unread archive]

    def index
      return unless authorize_notifications!(recipient: @recipient)

      @notifications = Notification.for_recipient(@recipient).active.newest_first.limit(100)
    end

    def show
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)
    end

    def mark_read
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)

      @notification.mark_read!
      redirect_back fallback_location: notification_path(@notification), notice: "Notification marked read."
    end

    def mark_unread
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)

      @notification.mark_unread!
      redirect_back fallback_location: notification_path(@notification), notice: "Notification marked unread."
    end

    def archive
      return unless authorize_notifications!(recipient: @recipient, notification: @notification)

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
  end
end
