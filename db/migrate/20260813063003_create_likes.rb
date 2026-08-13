class CreateLikes < ActiveRecord::Migration[8.0]
  def change
    add_index :profiles, [ :id, :brand_id ], unique: true, name: "idx_profiles_on_id_brand"

    create_table :likes do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :liker_profile, null: false, foreign_key: false
      t.references :liked_profile, null: false, foreign_key: false
      t.integer :kind, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :likes, [ :brand_id, :liker_profile_id, :liked_profile_id ],
      unique: true,
      where: "deleted_at IS NULL",
      name: "idx_likes_active_pair"
    add_check_constraint :likes, "liker_profile_id <> liked_profile_id", name: "chk_likes_not_self"
    add_foreign_key :likes, :profiles,
      column: [ :liker_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_likes_liker_profile_tenant"
    add_foreign_key :likes, :profiles,
      column: [ :liked_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_likes_liked_profile_tenant"
  end
end
