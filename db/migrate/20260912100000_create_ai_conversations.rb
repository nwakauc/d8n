class CreateAiConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_conversations do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: true
      t.string :assistant_key, null: false
      t.integer :status, null: false, default: 0
      t.integer :safety_status, null: false, default: 0
      t.datetime :last_message_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :ai_conversations, [ :brand_membership_id, :assistant_key ],
      unique: true, where: "deleted_at IS NULL", name: "index_ai_conversations_active_member_assistant"
    add_index :ai_conversations, [ :brand_id, :deleted_at ]

    create_table :ai_messages do |t|
      t.references :ai_conversation, null: false, foreign_key: true
      t.integer :role, null: false
      t.text :content, null: false
      t.string :client_message_id
      t.string :provider
      t.string :model
      t.timestamps
    end

    add_index :ai_messages, [ :ai_conversation_id, :created_at ]
    add_index :ai_messages, [ :ai_conversation_id, :client_message_id ],
      unique: true, where: "client_message_id IS NOT NULL", name: "index_ai_messages_client_idempotency"

    create_table :ai_usage_events do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: true
      t.references :ai_conversation, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :model, null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :total_tokens
      t.string :request_key, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    add_index :ai_usage_events, :request_key, unique: true
    add_index :ai_usage_events, [ :brand_membership_id, :created_at ]
  end
end
