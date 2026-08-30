class EnforceOneActiveAdminAssignmentPerBrand < ActiveRecord::Migration[8.0]
  def change
    add_index :admin_assignments, [ :admin_user_id, :brand_id ],
      unique: true,
      where: "deleted_at IS NULL AND status = 0",
      name: "index_admin_assignments_on_one_active_role_per_brand"
  end
end
