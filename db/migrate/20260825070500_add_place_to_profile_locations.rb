class AddPlaceToProfileLocations < ActiveRecord::Migration[8.1]
  def change
    add_reference :profile_locations, :place, foreign_key: true, null: true

    remove_check_constraint :profile_locations, name: "chk_profile_locations_source"
    add_check_constraint :profile_locations,
      "source IN ('device', 'manual', 'imported', 'place')",
      name: "chk_profile_locations_source"
  end
end
