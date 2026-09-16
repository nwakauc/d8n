class CreateMigrationMediaObjectRefs < ActiveRecord::Migration[8.1]
  def change
    create_table :migration_media_object_refs do |t|
      # Canonical identity of one source storage object/blob (ADR 0027).
      # Never a D8N primary key; source ids are text for the same reason as
      # legacy_references.source_id.
      t.string :source_system, null: false
      t.string :source_blob_id, null: false

      # Integrity metadata only — NOT domain identity. Two domain photos with an
      # identical checksum are still two photos; this table never deduplicates
      # them (ADR 0027).
      t.string :checksum
      t.bigint :byte_size, null: false, default: 0
      t.string :content_type

      # Fast drift key over (checksum, byte_size, content_type). A rerun whose
      # source blob metadata differs fails closed.
      t.string :source_fingerprint, null: false
      t.string :importer_version, null: false

      # Pass-1 preflight outcome and the pass-2 transfer lifecycle. Transfer
      # state lives here because the blob, not the attachment, is what gets
      # copied (ADR 0027).
      t.integer :preflight_state, null: false, default: 0
      t.integer :transfer_state, null: false, default: 0
      t.datetime :transferred_at
      t.string :failure_code

      t.timestamps
    end

    add_index :migration_media_object_refs, [ :source_system, :source_blob_id ],
      unique: true, name: "idx_migration_media_object_refs_source_key"
  end
end
