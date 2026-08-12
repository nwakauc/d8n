class CreateBrandDomains < ActiveRecord::Migration[8.0]
  def change
    create_table :brand_domains do |t|
      t.references :brand, null: false, foreign_key: true
      t.string :host, null: false
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :brand_domains, :host, unique: true, where: "deleted_at IS NULL"
  end
end
