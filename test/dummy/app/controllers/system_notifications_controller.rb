class SystemNotificationsController < ApplicationController
  def index
    @system_notifications = SystemNotification.order(created_at: :desc)
  end

  def show
    @system_notification = SystemNotification.find(params[:id])
  end

  def new
    @system_notification = SystemNotification.new
  end

  def create
    @system_notification = SystemNotification.new(system_notification_params)
    @system_notification.creator = current_user

    if @system_notification.save
      broadcast_system_notification(@system_notification)
      redirect_to system_notification_path(@system_notification), notice: "System notification created and sent to all users."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def system_notification_params
    params.require(:system_notification).permit(:title, :body)
  end

  def broadcast_system_notification(system_notification)
    RecordingStudioNotifications.notify_fan_out(
      recipient_scope: :all_users,
      notification_type: :system_announcement,
      actor: current_user,
      notifiable: system_notification,
      title: system_notification.title,
      body: system_notification.body.to_s.truncate(200),
      url: system_notification_path(system_notification),
      idempotency_key: "system-notification-#{system_notification.id}"
    )
  end
end
