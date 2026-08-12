class CreateAdminUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_users do |t|
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end
  end
end
