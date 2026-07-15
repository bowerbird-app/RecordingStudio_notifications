# frozen_string_literal: true

class RecreateRecordingStudioAccessesForAccessible < ActiveRecord::Migration[8.1]
  def up
    create_table :recording_studio_accesses, id: :uuid, if_not_exists: true do |t|
      t.string :actor_type, null: false
      t.uuid :actor_id, null: false
      t.integer :role, null: false, default: 0
      t.datetime :created_at, null: false
    end

    add_index :recording_studio_accesses,
              %i[actor_type actor_id],
              name: "index_recording_studio_accesses_on_actor",
              if_not_exists: true

    add_index :recording_studio_accesses,
              %i[actor_type actor_id role],
              name: "index_recording_studio_accesses_on_actor_and_role",
              if_not_exists: true
  end

  def down
    drop_table :recording_studio_accesses, if_exists: true
  end
end
