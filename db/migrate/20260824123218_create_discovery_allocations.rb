class CreateDiscoveryAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :discovery_allocations do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: false
      t.references :viewer_profile, null: false, foreign_key: false
      t.string :surface_key, null: false
      t.date :allocation_date, null: false
      t.string :time_zone, null: false
      t.integer :daily_limit, null: false
      t.string :strategy_key, null: false
      t.string :policy_key, null: false
      t.datetime :finalized_at, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :discovery_allocations,
      [ :brand_id, :brand_membership_id, :surface_key, :allocation_date ],
      unique: true,
      name: "idx_discovery_allocations_unique_member_surface_day"
    add_index :discovery_allocations,
      [ :id, :brand_id ],
      unique: true,
      name: "idx_discovery_allocations_on_id_brand"
    add_check_constraint :discovery_allocations,
      "daily_limit > 0",
      name: "chk_discovery_allocations_positive_limit"

    add_foreign_key :discovery_allocations, :brand_memberships,
      column: [ :brand_membership_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_discovery_allocations_membership_tenant"
    add_foreign_key :discovery_allocations, :profiles,
      column: [ :viewer_profile_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_discovery_allocations_viewer_tenant"
  end
end
