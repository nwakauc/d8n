class CreateProfilePreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :profile_preferences do |t|
      t.references :profile, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.integer :min_age
      t.integer :max_age
      t.jsonb :interested_in, null: false, default: []
      t.integer :max_distance_km
      t.string :country
      t.string :relationship_intent
      t.jsonb :metadata, null: false, default: {}
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_preferences, :profile_id,
      unique: true,
      where: "deleted_at IS NULL",
      name: "index_profile_preferences_on_active_profile_id"
    add_index :profile_preferences, [ :user_id, :brand_id ],
      unique: true,
      where: "deleted_at IS NULL",
      name: "index_profile_preferences_on_active_user_brand"
    add_index :profile_preferences, [ :brand_id, :min_age, :max_age ]
    add_index :profile_preferences, :deleted_at
  end
end
