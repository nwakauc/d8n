class CreateAdminMfaCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_mfa_credentials do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.text :secret, null: false
      t.jsonb :recovery_code_digests, null: false, default: []
      t.datetime :confirmed_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :admin_mfa_credentials, :admin_user_id,
      unique: true,
      where: "deleted_at IS NULL",
      name: "index_admin_mfa_credentials_on_kept_admin"

    add_reference :sessions, :admin_mfa_credential,
      foreign_key: true,
      index: true
    add_column :sessions, :admin_mfa_verified_at, :datetime
  end
end
