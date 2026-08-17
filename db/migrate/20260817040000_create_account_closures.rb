class CreateAccountClosures < ActiveRecord::Migration[8.0]
  # Durable record of a brand-level account closure. Tracks the target, the
  # membership that was closed (unique — one closure per membership instance, which
  # also gives idempotency), the profile whose media must be purged, and the async
  # media-purge outcome so a failed purge is operationally discoverable rather than
  # silently "done". Closure is one-way at the product API; a returning identity
  # rejoins by creating a new membership, which can be closed again (new row).
  def change
    create_table :account_closures do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: true, index: { unique: true }
      t.references :profile, null: true, foreign_key: true
      t.integer :media_purge_state, null: false, default: 0
      t.datetime :media_purged_at

      t.timestamps
    end
  end
end
