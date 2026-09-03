class CreateMigrationMediaAttachmentRefs < ActiveRecord::Migration[8.1]
  def change
    create_table :migration_media_attachment_refs do |t|
      # Canonical identity of one source attachment/use (ADR 0027). Distinct
      # from the blob it points at: one blob may back many attachments.
      t.string :source_system, null: false
      t.string :source_attachment_id, null: false

      t.references :media_object_ref, null: false, foreign_key: { to_table: :migration_media_object_refs }

      # The source record the attachment hangs off — for Date9ja profile photos,
      # entity "photo" and the legacy Photo.id. This is the SOURCE use graph;
      # source->destination domain identity stays in Migration::ReferenceMap.
      t.string :source_record_entity, null: false
      t.string :source_record_id, null: false
      t.string :attachment_name, null: false

      t.integer :preflight_state, null: false, default: 0
      t.string :failure_code
      t.string :importer_version, null: false

      t.timestamps
    end

    add_index :migration_media_attachment_refs, [ :source_system, :source_attachment_id ],
      unique: true, name: "idx_migration_media_attachment_refs_source_key"
    add_index :migration_media_attachment_refs, [ :source_system, :source_record_entity, :source_record_id ],
      name: "idx_migration_media_attachment_refs_record"
  end
end
