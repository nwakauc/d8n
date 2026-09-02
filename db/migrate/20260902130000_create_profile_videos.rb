class CreateProfileVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :profile_videos do |t|
      t.references :profile, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.string :public_id, null: false
      t.integer :status, null: false, default: 0
      t.integer :visibility, null: false, default: 0
      t.integer :processing_state, null: false, default: 0
      t.integer :duration_seconds
      t.datetime :processed_at
      t.datetime :deleted_at
      t.bigint :deleted_by_id
      t.string :deletion_reason
      t.timestamps
    end

    add_index :profile_videos, :public_id, unique: true
    # One profile video per profile (mirrors Date9ja's one-per-user).
    add_index :profile_videos, :profile_id, unique: true, where: "deleted_at IS NULL",
      name: "idx_profile_videos_one_per_profile"
  end
end
