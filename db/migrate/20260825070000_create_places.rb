class CreatePlaces < ActiveRecord::Migration[8.1]
  def change
    create_table :places do |t|
      t.references :parent, foreign_key: { to_table: :places }, null: true
      t.integer :kind, null: false
      t.string :country_code, limit: 2, null: false
      t.string :name, null: false
      t.string :code, null: false
      t.decimal :latitude, precision: 10, scale: 7, null: false
      t.decimal :longitude, precision: 10, scale: 7, null: false
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :places, [ :country_code, :kind ]
    add_index :places, [ :parent_id, :code ],
      unique: true,
      where: "deleted_at IS NULL",
      name: "idx_places_active_parent_code"
    add_index :places, :country_code,
      unique: true,
      where: "kind = 0 AND deleted_at IS NULL",
      name: "idx_places_unique_country"

    add_check_constraint :places, "kind BETWEEN 0 AND 3", name: "chk_places_kind"
    add_check_constraint :places, "status BETWEEN 0 AND 1", name: "chk_places_status"
    add_check_constraint :places, "latitude BETWEEN -90 AND 90", name: "chk_places_latitude"
    add_check_constraint :places, "longitude BETWEEN -180 AND 180", name: "chk_places_longitude"
    add_check_constraint :places, "char_length(country_code) = 2", name: "chk_places_country_code_length"
    add_check_constraint :places, "(kind = 0 AND parent_id IS NULL) OR (kind != 0 AND parent_id IS NOT NULL)",
      name: "chk_places_country_has_no_parent"
  end
end
