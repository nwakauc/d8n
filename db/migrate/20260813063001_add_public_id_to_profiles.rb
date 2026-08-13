class AddPublicIdToProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :profiles, :public_id, :uuid, null: false, default: -> { "gen_random_uuid()" }
    add_index :profiles, :public_id, unique: true
  end
end
