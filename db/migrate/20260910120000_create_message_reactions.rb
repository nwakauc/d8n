class CreateMessageReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :message_reactions do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.references :reactor_profile, null: false, foreign_key: { to_table: :profiles }
      t.string :emoji, null: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :message_reactions, [ :message_id, :reactor_profile_id, :emoji ], unique: true,
      name: "idx_message_reactions_unique"
  end
end
