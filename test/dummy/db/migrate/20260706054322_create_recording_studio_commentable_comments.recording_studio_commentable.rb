# frozen_string_literal: true

# This migration comes from recording_studio_commentable (originally 20260301000001)
# Migration for the recording_studio_comments table.
#
# Each comment is also wrapped in a RecordingStudio::Recording child recording,
# so the recording carries the history (created_at, parent, root). The comment
# row itself stores the body text and author reference.
#
class CreateRecordingStudioCommentableComments < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_comments, id: :uuid do |t|
      t.text :body, null: false

      # Polymorphic author (User, ServiceAccount, etc.)
      t.string :author_type
      t.uuid   :author_id

      t.timestamps
    end

    add_index :recording_studio_comments, %i[author_type author_id]
  end
end
