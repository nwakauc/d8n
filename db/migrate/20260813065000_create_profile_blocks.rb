class CreateProfileBlocks < ActiveRecord::Migration[8.0]
  def change
    create_table :profile_blocks do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :blocker_profile, null: false, foreign_key: false
      t.references :blocked_profile, null: false, foreign_key: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_blocks, [ :brand_id, :blocker_profile_id, :blocked_profile_id ],
      unique: true,
      where: "deleted_at IS NULL",
      name: "idx_profile_blocks_active_pair"
    add_index :profile_blocks, [ :brand_id, :blocker_profile_id ],
      where: "deleted_at IS NULL",
      name: "idx_profile_blocks_active_outgoing"
    add_index :profile_blocks, [ :brand_id, :blocked_profile_id ],
      where: "deleted_at IS NULL",
      name: "idx_profile_blocks_active_incoming"
    add_check_constraint :profile_blocks,
      "blocker_profile_id <> blocked_profile_id",
      name: "chk_profile_blocks_not_self"
    add_foreign_key :profile_blocks, :profiles,
      column: [ :blocker_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_profile_blocks_blocker_tenant"
    add_foreign_key :profile_blocks, :profiles,
      column: [ :blocked_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_profile_blocks_blocked_tenant"
  end
end
