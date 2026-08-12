class CreateAdminRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_roles do |t|
      t.string :name, null: false
      t.string :description
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :admin_roles, :name, unique: true, where: "deleted_at IS NULL"
  end
end
