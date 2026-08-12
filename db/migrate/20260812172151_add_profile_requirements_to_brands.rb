class AddProfileRequirementsToBrands < ActiveRecord::Migration[8.0]
  def change
    add_column :brands, :profile_requirements, :jsonb, null: false, default: {
      profile_fields: [ "display_name", "birthdate", "gender" ],
      preference_fields: [ "min_age", "max_age", "interested_in" ],
      collections: [ "photos" ]
    }
  end
end
