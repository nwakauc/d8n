class CreateCredentialPasswordHashes < ActiveRecord::Migration[8.0]
  def change
    create_table :credential_password_hashes, id: false do |t|
      t.bigint :credential_id, null: false, primary_key: true
      t.integer :credential_kind, null: false, default: 0
      t.string :password_hash, null: false
      t.datetime :password_changed_at, null: false

      t.timestamps

      t.check_constraint "credential_kind = 0", name: "chk_password_hash_credential_kind"
    end

    add_index :credentials, [ :id, :kind ], unique: true, name: "idx_credentials_on_id_kind"
    add_foreign_key :credential_password_hashes, :credentials,
      column: [ :credential_id, :credential_kind ],
      primary_key: [ :id, :kind ],
      name: "fk_password_hash_credential_kind"
  end
end
