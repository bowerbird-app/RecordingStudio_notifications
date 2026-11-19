# frozen_string_literal: true

class AddInboundRepliesToRecordingStudioNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_notifications_notifications, :thread_key, :string

    create_table :recording_studio_notifications_replies, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :notification_id, null: false
      t.string :channel, null: false
      t.string :idempotency_key, null: false
      t.string :status, null: false
      t.string :reason

      t.timestamps
    end

    add_index :recording_studio_notifications_replies, %i[channel idempotency_key],
              unique: true,
              name: "idx_rsn_replies_channel_idempotency"
    add_index :recording_studio_notifications_replies, :notification_id,
              name: "idx_rsn_replies_notification"
    add_foreign_key :recording_studio_notifications_replies,
                    :recording_studio_notifications_notifications,
                    column: :notification_id
  end
end
