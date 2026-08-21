class CreateFindProfileExposures < ActiveRecord::Migration[8.0]
  def change
    create_table :find_profile_exposures do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: false
      t.references :viewer_profile, null: false, foreign_key: false
      t.references :candidate_profile, null: false, foreign_key: false
      t.date :exposure_date, null: false

      t.timestamps
    end

    add_index :find_profile_exposures,
      [ :brand_id, :brand_membership_id, :candidate_profile_id, :exposure_date ],
      unique: true,
      name: "idx_find_exposures_unique_member_candidate_day"
    add_index :find_profile_exposures,
      [ :brand_id, :brand_membership_id, :exposure_date ],
      name: "idx_find_exposures_member_day"
    add_check_constraint :find_profile_exposures,
      "viewer_profile_id <> candidate_profile_id",
      name: "chk_find_exposures_not_self"

    add_foreign_key :find_profile_exposures, :brand_memberships,
      column: [ :brand_membership_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_find_exposures_membership_tenant"
    add_foreign_key :find_profile_exposures, :profiles,
      column: [ :viewer_profile_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_find_exposures_viewer_tenant"
    add_foreign_key :find_profile_exposures, :profiles,
      column: [ :candidate_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_find_exposures_candidate_tenant"
  end
end
