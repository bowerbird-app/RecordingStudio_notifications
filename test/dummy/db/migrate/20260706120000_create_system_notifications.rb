class CreateSystemNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :system_notifications, id: :uuid do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.references :creator, type: :uuid, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :system_notifications, :created_at
  end
end
