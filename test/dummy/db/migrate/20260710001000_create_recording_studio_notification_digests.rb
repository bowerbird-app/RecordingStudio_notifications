# frozen_string_literal: true

class CreateRecordingStudioNotificationDigests < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_notifications_digests, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :recipient_type, null: false
      t.uuid :recipient_id, null: false
      t.string :notification_type, null: false
      t.uuid :root_recording_id
      t.string :cadence, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :period_starts_at, null: false
      t.datetime :period_ends_at, null: false
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :recording_studio_notifications_digests,
              "recipient_type, recipient_id, notification_type, COALESCE(root_recording_id, '00000000-0000-0000-0000-000000000000'::uuid), cadence, period_starts_at",
              unique: true,
              where: "status = 'pending'",
              name: "idx_dummy_rsn_pending_digest_bucket"
    add_index :recording_studio_notifications_digests, %i[status period_ends_at],
              name: "idx_dummy_rsn_digests_status_period_end"

    create_table :recording_studio_notifications_digest_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :digest_id, null: false
      t.uuid :notification_id, null: false

      t.timestamps
    end

    add_index :recording_studio_notifications_digest_items, :notification_id,
              unique: true,
              name: "idx_dummy_rsn_digest_items_notification"
    add_index :recording_studio_notifications_digest_items, %i[digest_id notification_id],
              unique: true,
              name: "idx_dummy_rsn_digest_items_digest_notification"
    add_foreign_key :recording_studio_notifications_digest_items,
                    :recording_studio_notifications_digests,
                    column: :digest_id
    add_foreign_key :recording_studio_notifications_digest_items,
                    :recording_studio_notifications_notifications,
                    column: :notification_id
  end
end
