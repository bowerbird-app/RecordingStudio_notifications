# frozen_string_literal: true

class CreateRecordingStudioNotificationsCadencePreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_notifications_cadence_preferences, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :recipient_type, null: false
      t.uuid :recipient_id, null: false
      t.string :notification_type, null: false
      t.string :cadence, null: false, default: "every_notification"

      t.timestamps
    end

    add_index :recording_studio_notifications_cadence_preferences,
              %i[recipient_type recipient_id notification_type],
              unique: true,
              name: "idx_dummy_rsn_cadence_preferences_recipient_type"
  end
end
