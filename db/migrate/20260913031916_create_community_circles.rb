class CreateCommunityCircles < ActiveRecord::Migration[8.0]
  def change
    create_table :community_circles do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :creator_profile, null: false, foreign_key: { to_table: :profiles }
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.string :name, null: false
      t.text :description, null: false
      t.string :category, null: false
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :community_circles, :public_id, unique: true
    add_index :community_circles, [ :brand_id, :status, :created_at ]
  end
end
