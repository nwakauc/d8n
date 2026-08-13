class CreateMatches < ActiveRecord::Migration[8.0]
  def change
    create_table :matches do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :profile_a, null: false, foreign_key: false
      t.references :profile_b, null: false, foreign_key: false
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :matches, :public_id, unique: true
    add_index :matches, [ :brand_id, :profile_a_id, :profile_b_id ],
      unique: true,
      where: "deleted_at IS NULL AND status = 0",
      name: "idx_matches_active_pair"
    add_index :matches, [ :brand_id, :profile_a_id, :created_at ]
    add_index :matches, [ :brand_id, :profile_b_id, :created_at ]
    add_check_constraint :matches, "profile_a_id < profile_b_id", name: "chk_matches_canonical_pair"
    add_foreign_key :matches, :profiles,
      column: [ :profile_a_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_matches_profile_a_tenant"
    add_foreign_key :matches, :profiles,
      column: [ :profile_b_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_matches_profile_b_tenant"
  end
end
