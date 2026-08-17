class CreateAccountEnforcements < ActiveRecord::Migration[8.0]
  # A durable brand-level enforcement (suspension) record. It links the target
  # user/membership/profile, the acting admin, an optional originating report, and
  # a short reason, plus reversal provenance. Kept separate from the report
  # lifecycle: a report being `actioned` never implies an enforcement. Only one
  # active (un-reverted) enforcement may exist per user per brand, which gives
  # idempotency/conflict handling without distributed locking. Platform-level bans
  # are intentionally not modelled yet (no global admin authority exists).
  def change
    create_table :account_enforcements do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: true
      t.references :profile, null: true, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.references :report, null: true, foreign_key: true
      t.references :reverted_by_admin_user, null: true, foreign_key: { to_table: :admin_users }
      t.text :reason
      t.datetime :reverted_at

      t.timestamps
    end

    add_index :account_enforcements, [ :brand_id, :user_id ],
      unique: true, where: "reverted_at IS NULL",
      name: "idx_account_enforcements_active_unique"
  end
end
