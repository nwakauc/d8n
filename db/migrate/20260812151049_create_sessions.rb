class CreateSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :brand, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :device_name
      t.string :ip_address
      t.text :user_agent
      t.datetime :last_used_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :sessions, :token_digest, unique: true
    add_index :sessions, [ :brand_id, :user_id, :revoked_at ]
  end
end
