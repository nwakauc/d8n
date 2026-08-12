class CreateCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.references :identity_identifier, null: false, foreign_key: true
      t.integer :kind, null: false
      t.integer :status, null: false, default: 0
      t.datetime :verified_at
      t.datetime :last_used_at
      t.jsonb :metadata, null: false, default: {}
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :credentials, [ :user_id, :kind, :identity_identifier_id ],
      unique: true,
      where: "deleted_at IS NULL",
      name: "index_credentials_on_active_user_kind_identifier"
  end
end
