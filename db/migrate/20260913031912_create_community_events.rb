class CreateCommunityEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :community_events do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :organizer_profile, null: false, foreign_key: { to_table: :profiles }
      t.uuid :public_id, null: false, default: -> { "gen_random_uuid()" }
      t.string :title, null: false
      t.text :description, null: false
      t.string :city, null: false
      t.string :venue
      t.datetime :starts_at, null: false
      t.integer :capacity
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :community_events, :public_id, unique: true
    add_index :community_events, [ :brand_id, :status, :starts_at ]
  end
end
