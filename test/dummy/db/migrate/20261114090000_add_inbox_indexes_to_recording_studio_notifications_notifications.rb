# frozen_string_literal: true

class AddInboxIndexesToRecordingStudioNotificationsNotifications < ActiveRecord::Migration[8.1]
  def change
    add_index :recording_studio_notifications_notifications,
              %i[recipient_type recipient_id created_at id],
              order: { created_at: :desc, id: :desc },
              where: "archived_at IS NULL AND inbox = TRUE",
              name: "idx_dummy_rsn_notifications_inbox"

    add_index :recording_studio_notifications_notifications,
              %i[recipient_type recipient_id],
              where: "read_at IS NULL AND cleared_at IS NULL AND archived_at IS NULL AND inbox = TRUE",
              name: "idx_dummy_rsn_notifications_unread"
  end
end
