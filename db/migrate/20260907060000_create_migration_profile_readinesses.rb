class CreateMigrationProfileReadinesses < ActiveRecord::Migration[8.1]
  def change
    create_table :migration_profile_readinesses do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :profile, null: true, foreign_key: true, index: false

      t.string :source_system, null: false
      t.string :source_entity, null: false
      t.string :source_id, null: false
      t.integer :disposition, null: false
      t.jsonb :reason_codes, null: false, default: []
      t.jsonb :applied_fields, null: false, default: []
      t.string :importer_version, null: false
      t.string :source_fingerprint
      t.datetime :assessed_at, null: false
      t.datetime :publication_applied_at

      t.timestamps
    end

    add_index :migration_profile_readinesses,
      [ :source_system, :source_entity, :source_id ],
      unique: true,
      name: "idx_migration_profile_readiness_source"
    add_index :migration_profile_readinesses, :profile_id,
      unique: true,
      where: "profile_id IS NOT NULL",
      name: "idx_migration_profile_readiness_profile"
    add_check_constraint :migration_profile_readinesses,
      "disposition BETWEEN 0 AND 3",
      name: "chk_migration_profile_readiness_disposition"
    add_check_constraint :migration_profile_readinesses,
      "jsonb_typeof(reason_codes) = 'array'",
      name: "chk_migration_profile_readiness_reasons_array"
    add_check_constraint :migration_profile_readinesses,
      "jsonb_typeof(applied_fields) = 'array'",
      name: "chk_migration_profile_readiness_applied_fields_array"
    add_check_constraint :migration_profile_readinesses,
      "(profile_id IS NULL AND user_id IS NULL) OR (profile_id IS NOT NULL AND user_id IS NOT NULL)",
      name: "chk_migration_profile_readiness_owner_pair"

    add_foreign_key :migration_profile_readinesses, :profiles,
      column: [ :profile_id, :user_id, :brand_id ],
      primary_key: [ :id, :user_id, :brand_id ],
      name: "fk_migration_profile_readiness_profile_tenant"
  end
end
