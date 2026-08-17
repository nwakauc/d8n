class CreateMessages < ActiveRecord::Migration[8.0]
  # Persisted text content for a match-gated conversation (ADR 0010 Slice 2, beta
  # subset). Messages belong to a brand and a conversation and are authored by a
  # brand profile, never a raw network user. Content is plain text only; read
  # state, reactions, edits, attachments, and realtime delivery are deliberately
  # out of scope. `deleted_at` exists now so future retention/erasure can soft
  # delete without a schema change; nothing sets it yet.
  def change
    create_table :messages do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: false
      t.references :sender_profile, null: false, foreign_key: false
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.text :body, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :messages, :public_id, unique: true
    # Primary read pattern: newest-first history within one conversation, paged by
    # a stable (created_at DESC, id DESC) cursor. Partial on kept rows keeps any
    # future soft-deleted message out of the hot path.
    add_index :messages, [ :conversation_id, :created_at, :id ],
      where: "deleted_at IS NULL",
      name: "idx_messages_conversation_cursor"
    add_index :messages, [ :id, :brand_id ], unique: true, name: "idx_messages_on_id_brand"

    # Tenant-safe composite foreign keys: a message can only reference a
    # conversation and a sender profile in its own brand.
    add_foreign_key :messages, :conversations,
      column: [ :conversation_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_messages_conversation_tenant"
    add_foreign_key :messages, :profiles,
      column: [ :sender_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_messages_sender_tenant"
  end
end
