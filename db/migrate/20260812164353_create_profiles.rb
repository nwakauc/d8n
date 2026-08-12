class CreateProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.references :brand_membership, null: false, foreign_key: true
      t.string :display_name
      t.text :bio
      t.date :birthdate
      t.string :gender
      t.integer :status, null: false, default: 0
      t.integer :visibility, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profiles, [ :user_id, :brand_id ], unique: true, where: "deleted_at IS NULL"
    add_index :profiles, [ :brand_id, :status, :visibility, :created_at ]
    add_index :profiles, :deleted_at
  end
end
