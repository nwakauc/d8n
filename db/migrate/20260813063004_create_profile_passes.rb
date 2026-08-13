class CreateProfilePasses < ActiveRecord::Migration[8.0]
  def change
    create_table :profile_passes do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :passer_profile, null: false, foreign_key: false
      t.references :passed_profile, null: false, foreign_key: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_passes, [ :brand_id, :passer_profile_id, :passed_profile_id ],
      unique: true,
      where: "deleted_at IS NULL",
      name: "idx_profile_passes_active_pair"
    add_check_constraint :profile_passes, "passer_profile_id <> passed_profile_id", name: "chk_profile_passes_not_self"
    add_foreign_key :profile_passes, :profiles,
      column: [ :passer_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_profile_passes_passer_tenant"
    add_foreign_key :profile_passes, :profiles,
      column: [ :passed_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_profile_passes_passed_tenant"
  end
end
