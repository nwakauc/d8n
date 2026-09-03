class HardenMigrationMediaObjectRefs < ActiveRecord::Migration[8.1]
  def change
    change_column_default :migration_media_object_refs, :byte_size, from: 0, to: nil
    change_column_null :migration_media_object_refs, :byte_size, true

    add_check_constraint :migration_media_object_refs,
      "byte_size IS NULL OR byte_size > 0", name: "chk_migration_media_object_refs_positive_size",
      if_not_exists: true
    add_check_constraint :migration_media_object_refs,
      "preflight_state BETWEEN 0 AND 3", name: "chk_migration_media_object_refs_preflight_state",
      if_not_exists: true
    add_check_constraint :migration_media_object_refs,
      "transfer_state BETWEEN 0 AND 3", name: "chk_migration_media_object_refs_transfer_state",
      if_not_exists: true
    add_check_constraint :migration_media_attachment_refs,
      "preflight_state BETWEEN 0 AND 3", name: "chk_migration_media_attachment_refs_preflight_state",
      if_not_exists: true
  end
end
