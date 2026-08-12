class CreateAdminAssignments < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_assignments do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.references :admin_role, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :admin_assignments, [ :admin_user_id, :brand_id, :admin_role_id ],
      unique: true,
      where: "deleted_at IS NULL",
      name: "index_admin_assignments_on_active_role_scope"
  end
end
