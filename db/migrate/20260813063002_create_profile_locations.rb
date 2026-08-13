class CreateProfileLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :profile_locations do |t|
      t.references :profile, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.decimal :latitude, precision: 10, scale: 7, null: false
      t.decimal :longitude, precision: 10, scale: 7, null: false
      t.integer :accuracy_meters, null: false
      t.string :source, limit: 32, null: false
      t.datetime :captured_at, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_locations, :profile_id,
      unique: true,
      where: "deleted_at IS NULL",
      name: "idx_profile_locations_active_profile"
    add_index :profile_locations, [ :brand_id, :latitude, :longitude ],
      where: "deleted_at IS NULL",
      name: "idx_profile_locations_active_coordinates"
    add_check_constraint :profile_locations,
      "latitude BETWEEN -90 AND 90",
      name: "chk_profile_locations_latitude"
    add_check_constraint :profile_locations,
      "longitude BETWEEN -180 AND 180",
      name: "chk_profile_locations_longitude"
    add_check_constraint :profile_locations,
      "accuracy_meters BETWEEN 0 AND 100000",
      name: "chk_profile_locations_accuracy"
    add_check_constraint :profile_locations,
      "source IN ('device', 'manual', 'imported')",
      name: "chk_profile_locations_source"
    add_foreign_key :profile_locations, :profiles,
      column: [ :profile_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_profile_locations_profile_tenant"
  end
end
