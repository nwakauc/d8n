class CreateHooks < ActiveRecord::Migration[8.0]
  # A HookUs "🔥 Hook": a stronger-intent interaction than a Like. The sender
  # gets exactly ONE unsolicited opening message (`message`) to a recipient and is
  # then locked out until the recipient engages. The recipient's first reply
  # accepts the Hook, at which point a normal Match + Conversation are created and
  # `conversation_id` is linked — all subsequent chat flows through the existing
  # messaging tables, so there is only one chat system (see ADR 0015).
  #
  # Pre-acceptance state lives entirely here (no Match/Conversation/Message rows
  # exist yet), which is what makes the sender lockout enforceable at the data
  # layer: with no conversation, no message endpoint is reachable, and the unique
  # (sender, recipient) index makes a second Hook impossible.
  def change
    create_table :hooks do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :sender_profile, null: false, foreign_key: false
      t.references :recipient_profile, null: false, foreign_key: false
      # Set atomically when the recipient's first reply accepts the Hook.
      t.references :conversation, null: true, foreign_key: false
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.text :message, null: false
      # pending / accepted / declined / expired / cancelled (see Hook model).
      t.integer :status, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :declined_at
      # Present for future retention/erasure symmetry with the other interaction
      # tables; nothing sets it yet.
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :hooks, :public_id, unique: true
    # V1 conservative anti-spam: exactly one Hook per ordered (sender -> recipient)
    # pair, ever. This single index simultaneously blocks a duplicate pending
    # Hook, a delete/resend loop (rows are never hard-deleted), a re-Hook after
    # decline/expiry, and concurrent duplicate creation (paired with a
    # RecordNotUnique rescue in Hooks::SendHook).
    add_index :hooks, [ :brand_id, :sender_profile_id, :recipient_profile_id ],
      unique: true, name: "idx_hooks_sender_recipient"
    # Recipient inbox: live (pending) Hooks newest-first.
    add_index :hooks, [ :brand_id, :recipient_profile_id, :status, :created_at ],
      name: "idx_hooks_recipient_inbox"
    # Sender rate-limit window counting.
    add_index :hooks, [ :brand_id, :sender_profile_id, :created_at ],
      name: "idx_hooks_sender_created"
    add_index :hooks, [ :id, :brand_id ], unique: true, name: "idx_hooks_on_id_brand"

    # Tenant-safe composite foreign keys: a Hook can only reference profiles and a
    # conversation within its own brand.
    add_foreign_key :hooks, :profiles,
      column: [ :sender_profile_id, :brand_id ], primary_key: [ :id, :brand_id ],
      name: "fk_hooks_sender_tenant"
    add_foreign_key :hooks, :profiles,
      column: [ :recipient_profile_id, :brand_id ], primary_key: [ :id, :brand_id ],
      name: "fk_hooks_recipient_tenant"
    add_foreign_key :hooks, :conversations,
      column: [ :conversation_id, :brand_id ], primary_key: [ :id, :brand_id ],
      name: "fk_hooks_conversation_tenant"

    add_check_constraint :hooks, "sender_profile_id <> recipient_profile_id", name: "chk_hooks_not_self"
  end
end
