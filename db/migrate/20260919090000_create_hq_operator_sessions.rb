class CreateHqOperatorSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :hq_operator_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.references :admin_mfa_credential, foreign_key: true
      t.string :token_digest, null: false
      t.string :device_name
      t.string :ip_address
      t.text :user_agent
      t.datetime :last_used_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :admin_mfa_verified_at
      t.datetime :revoked_at
      t.string :revocation_reason
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :hq_operator_sessions, :token_digest, unique: true
    add_index :hq_operator_sessions, [ :admin_user_id, :revoked_at ]
  end
end
