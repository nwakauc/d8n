class CreateCommunityCircleMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :community_circle_memberships do |t|
      t.references :community_circle, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :community_circle_memberships, [ :community_circle_id, :profile_id ], unique: true, where: "deleted_at IS NULL", name: "idx_community_circle_memberships_active"
  end
end
