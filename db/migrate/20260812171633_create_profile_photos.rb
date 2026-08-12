class CreateProfilePhotos < ActiveRecord::Migration[8.0]
  def change
    create_table :profile_photos do |t|
      t.references :profile, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.integer :visibility, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :profile_photos, [ :profile_id, :position ], unique: true, where: "deleted_at IS NULL"
    add_index :profile_photos, [ :brand_id, :user_id, :deleted_at ]
    add_index :profile_photos, [ :brand_id, :status, :created_at ]
  end
end
