class CreateBrandMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :brand_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :brand_memberships, [ :user_id, :brand_id ], unique: true, where: "deleted_at IS NULL"
  end
end
