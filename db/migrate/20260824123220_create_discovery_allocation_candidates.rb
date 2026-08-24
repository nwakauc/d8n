class CreateDiscoveryAllocationCandidates < ActiveRecord::Migration[8.1]
  def change
    create_table :discovery_allocation_candidates do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :discovery_allocation, null: false, foreign_key: false
      t.references :candidate_profile, null: false, foreign_key: false
      t.integer :position, null: false
      t.jsonb :ranking_payload, null: false, default: {}
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :discovery_allocation_candidates,
      [ :discovery_allocation_id, :candidate_profile_id ],
      unique: true,
      name: "idx_discovery_allocation_candidates_unique_profile"
    add_index :discovery_allocation_candidates,
      [ :discovery_allocation_id, :position ],
      unique: true,
      name: "idx_discovery_allocation_candidates_unique_position"
    add_check_constraint :discovery_allocation_candidates,
      "position > 0",
      name: "chk_discovery_allocation_candidates_positive_position"

    add_foreign_key :discovery_allocation_candidates, :discovery_allocations,
      column: [ :discovery_allocation_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_discovery_allocation_candidates_allocation_tenant"
    add_foreign_key :discovery_allocation_candidates, :profiles,
      column: [ :candidate_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_discovery_allocation_candidates_profile_tenant"
  end
end
