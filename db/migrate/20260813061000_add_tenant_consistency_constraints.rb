class AddTenantConsistencyConstraints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_index :brand_memberships, [ :id, :user_id, :brand_id ],
      unique: true,
      name: "idx_memberships_on_id_user_brand",
      if_not_exists: true,
      algorithm: :concurrently
    add_index :profiles, [ :id, :user_id, :brand_id ],
      unique: true,
      name: "idx_profiles_on_id_user_brand",
      if_not_exists: true,
      algorithm: :concurrently

    add_foreign_key :profiles, :brand_memberships,
      column: [ :brand_membership_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_profiles_membership_tenant",
      if_not_exists: true,
      validate: false
    add_foreign_key :profile_preferences, :profiles,
      column: [ :profile_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_preferences_profile_tenant",
      if_not_exists: true,
      validate: false
    add_foreign_key :profile_photos, :profiles,
      column: [ :profile_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_photos_profile_tenant",
      if_not_exists: true,
      validate: false

    validate_foreign_key :profiles, name: "fk_profiles_membership_tenant"
    validate_foreign_key :profile_preferences, name: "fk_preferences_profile_tenant"
    validate_foreign_key :profile_photos, name: "fk_photos_profile_tenant"
  end

  def down
    remove_foreign_key :profile_photos, name: "fk_photos_profile_tenant", if_exists: true
    remove_foreign_key :profile_preferences, name: "fk_preferences_profile_tenant", if_exists: true
    remove_foreign_key :profiles, name: "fk_profiles_membership_tenant", if_exists: true

    remove_index :profiles, name: "idx_profiles_on_id_user_brand", if_exists: true, algorithm: :concurrently
    remove_index :brand_memberships, name: "idx_memberships_on_id_user_brand", if_exists: true, algorithm: :concurrently
  end
end
