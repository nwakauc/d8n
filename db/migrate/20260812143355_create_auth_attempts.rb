class CreateAuthAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :auth_attempts do |t|
      t.references :brand, null: true, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :identity_identifier, null: true, foreign_key: true
      t.references :credential, null: true, foreign_key: true
      t.integer :kind, null: false
      t.integer :result, null: false
      t.string :identifier, null: false
      t.string :ip_address
      t.text :user_agent
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :auth_attempts, [ :brand_id, :identifier, :created_at ]
    add_index :auth_attempts, [ :ip_address, :created_at ]
  end
end
