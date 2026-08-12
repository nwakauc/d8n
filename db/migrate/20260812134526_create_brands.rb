class CreateBrands < ActiveRecord::Migration[8.0]
  def change
    create_table :brands do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.integer :status, null: false, default: 0
      t.string :owner_type, null: false, default: "D8n"
      t.bigint :owner_id
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :brands, :slug, unique: true, where: "deleted_at IS NULL"
    add_index :brands, [ :owner_type, :owner_id ]
  end
end
