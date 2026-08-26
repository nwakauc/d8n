class CreateProfileOpeners < ActiveRecord::Migration[8.1]
  # D8N Opener: a brand-configurable catalog of curated opener *definitions*
  # (`key`/`text`), mirroring profile_prompts. A brand that requires curated
  # openers (see Hooks::Policy / BrandContract::OpenerConfiguration) resolves a
  # sender's chosen `key` to this row's `text` server-side at send time; the
  # resolved text is stored on the Hook itself (see add_profile_opener_to_hooks),
  # so catalog edits never rewrite history.
  def change
    create_table :profile_openers do |t|
      t.references :brand, null: false, foreign_key: true
      t.string :key, limit: 80, null: false
      t.string :text, limit: 200, null: false
      t.integer :status, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_openers, [ :brand_id, :key ],
      unique: true, where: "deleted_at IS NULL",
      name: "idx_profile_openers_active_key"
    # Composite unique key for the tenant-safe reference from hooks.
    add_index :profile_openers, [ :id, :brand_id ],
      unique: true, name: "idx_profile_openers_on_id_brand"
    add_check_constraint :profile_openers, "\"position\" >= 0",
      name: "chk_profile_openers_position"
  end
end
