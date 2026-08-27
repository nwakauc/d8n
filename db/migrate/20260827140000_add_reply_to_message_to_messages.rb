class AddReplyToMessageToMessages < ActiveRecord::Migration[8.1]
  # Reply-to-message: `reply_to_message_id` points at the message being
  # replied to (same conversation, enforced at the model level — see
  # Message#reply_to_message_is_same_conversation). `reply_snapshot` is a
  # frozen-at-send-time copy of the safe, non-live fields the reply preview
  # needs (sender profile id, message type, a body excerpt, attachment
  # metadata) — mirrors the same "evidence must not depend on live state"
  # pattern already used for report evidence (Trust::ReportTargets::MessageTarget)
  # so a reply preview keeps rendering correctly even if the original message
  # or its attachments are later deleted.
  def change
    add_column :messages, :reply_to_message_id, :bigint
    add_column :messages, :reply_snapshot, :jsonb, null: false, default: {}

    add_index :messages, :reply_to_message_id
    add_foreign_key :messages, :messages,
      column: [ :reply_to_message_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_messages_reply_to_message_tenant"
  end
end
