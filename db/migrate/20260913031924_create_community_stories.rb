class CreateCommunityStories < ActiveRecord::Migration[8.0]
  def change
    create_table :community_stories do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :author_profile, null: false, foreign_key: { to_table: :profiles }
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.string :title, null: false
      t.text :body, null: false
      t.string :content_type, null: false, default: "text"
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :community_stories, :public_id, unique: true
    add_index :community_stories, [ :brand_id, :status, :created_at ]
  end
end
