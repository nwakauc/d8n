class CreateIdentityIdentifiers < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_identifiers do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :kind, null: false
      t.string :normalized_value, null: false
      t.datetime :verified_at
      t.datetime :last_seen_at
      t.jsonb :metadata, null: false, default: {}
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :identity_identifiers, [ :kind, :normalized_value ],
      unique: true,
      where: "deleted_at IS NULL"
  end
end
