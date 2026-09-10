class AddDate9jaMessageHistoryFields < ActiveRecord::Migration[8.1]
  def change
    change_table :messages, bulk: true do |t|
      t.integer :kind, null: false, default: 0
      t.datetime :read_at
      t.datetime :edited_at
      t.string :source_media_reference
      t.jsonb :source_metadata, null: false, default: {}
    end
    add_index :messages, [ :conversation_id, :created_at, :id ], name: "idx_messages_history_cursor"
  end
end
