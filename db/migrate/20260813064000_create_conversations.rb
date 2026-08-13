class CreateConversations < ActiveRecord::Migration[8.0]
  def change
    add_index :matches, [ :id, :brand_id ], unique: true, name: "idx_matches_on_id_brand"

    create_table :conversations do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :match, null: false, foreign_key: false, index: { unique: true }
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :conversations, :public_id, unique: true
    add_index :conversations, [ :id, :brand_id ], unique: true, name: "idx_conversations_on_id_brand"
    add_index :conversations, [ :brand_id, :created_at, :public_id ], name: "idx_conversations_brand_cursor"
    add_foreign_key :conversations, :matches,
      column: [ :match_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_conversations_match_tenant"

    create_table :conversation_participants do |t|
      t.references :conversation, null: false, foreign_key: false
      t.references :profile, null: false, foreign_key: false
      t.references :user, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.datetime :last_read_at
      t.datetime :archived_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :conversation_participants, [ :conversation_id, :profile_id ],
      unique: true,
      name: "idx_conversation_participants_unique_profile"
    add_index :conversation_participants, [ :brand_id, :profile_id, :conversation_id ],
      name: "idx_conversation_participants_profile_list"
    add_foreign_key :conversation_participants, :conversations,
      column: [ :conversation_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_conversation_participants_conversation_tenant"
    add_foreign_key :conversation_participants, :profiles,
      column: [ :profile_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_conversation_participants_profile_tenant"
  end
end
