class CreateLegacyReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :legacy_references do |t|
      # (source_system, source_entity, source_id) is the foreign key we resolve
      # from. source_id is text: legacy PKs are not always integers and are never
      # used as D8N primary keys (see ADR 0022).
      t.string :source_system, null: false
      t.string :source_entity, null: false
      t.string :source_id, null: false
      # Hash/version of the source row at import time; updatable on re-import.
      t.string :source_fingerprint
      t.string :importer_version, null: false

      # Polymorphic destination as plain columns (no FK): the D8N record may be
      # soft-deleted independently; reconciliation checks resolvability.
      t.string :destination_type, null: false
      t.bigint :destination_id, null: false

      # Resolved brand for a brand-owned destination; null for a platform record.
      t.references :brand, foreign_key: true

      t.timestamps
    end

    # One destination per source row.
    add_index :legacy_references,
      [ :source_system, :source_entity, :source_id ],
      unique: true, name: "idx_legacy_references_source_key"

    # One source per destination — no accidental many-to-one merge.
    add_index :legacy_references,
      [ :source_system, :destination_type, :destination_id ],
      unique: true, name: "idx_legacy_references_destination_key"

    add_index :legacy_references, [ :source_system, :source_entity ],
      name: "idx_legacy_references_source_scan"
  end
end
