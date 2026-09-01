class AddMemberDirectoryQueryIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :brand_memberships, [ :brand_id, :created_at, :id ],
      name: "index_brand_memberships_on_brand_created_id"
    add_index :sessions, [ :brand_id, :user_id, :last_used_at ],
      name: "index_sessions_on_brand_user_last_used"
    add_index :profiles, "lower(display_name)",
      name: "index_profiles_on_lower_display_name"
    add_index :users, "lower(first_name)",
      name: "index_users_on_lower_first_name"
    add_index :users, "lower(last_name)",
      name: "index_users_on_lower_last_name"
  end
end
