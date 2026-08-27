class CreateMessageAttachments < ActiveRecord::Migration[8.1]
  # D8N Chat Media (image/video attachments on a Message). One row per attachment;
  # `message_id` is set at creation time (attach and send are the same operation —
  # see Messaging::SendMessage) so there is no "uploaded but orphaned from any
  # message" limbo row to clean up beyond the ordinary unattached-blob reclaim
  # (Media::PurgeUnattachedUploadsJob already covers the underlying blob).
  #
  # `media_kind` and `processing_state` mirror ProfilePhoto's proven shape.
  # Unlike ProfilePhoto there is no moderation `status`/`visibility` pair: chat
  # media is participant-only content (never public), so ordinary
  # conversation/match access is the only visibility gate (see
  # Messaging::ConversationAccess); reporting/blocking remain the safety net.
  def change
    create_table :message_attachments do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: false
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.integer :media_kind, null: false
      t.integer :position, null: false, default: 0
      t.integer :processing_state, null: false, default: 0
      t.string :content_type
      t.bigint :byte_size
      t.integer :width
      t.integer :height
      t.decimal :duration_seconds, precision: 10, scale: 3
      t.jsonb :metadata, null: false, default: {}
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :message_attachments, :public_id, unique: true
    add_index :message_attachments, [ :message_id, :position ], unique: true, where: "deleted_at IS NULL"
    add_index :message_attachments, [ :brand_id, :processing_state ]

    add_foreign_key :message_attachments, :messages,
      column: [ :message_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_message_attachments_message_tenant"
  end
end
