class CreateCommunityPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :community_posts do |t|
      t.references :community_circle, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.references :author_profile, null: false, foreign_key: { to_table: :profiles }
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.text :body, null: false
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :community_posts, :public_id, unique: true
    add_index :community_posts, [ :community_circle_id, :created_at ]
  end
end
