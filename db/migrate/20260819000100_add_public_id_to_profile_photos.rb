class AddPublicIdToProfilePhotos < ActiveRecord::Migration[8.1]
  # A stable, opaque identifier for a photo so other members can *reference* a
  # specific photo (e.g. to report it) without exposing the internal bigint id,
  # its R2 object key, or the mutable `position`. Additive and backfilled: added
  # nullable, every existing row gets a UUID, then made unique + NOT NULL. New
  # rows self-assign via ProfilePhoto#ensure_public_id, mirroring Profile/Message.
  def up
    add_column :profile_photos, :public_id, :string

    # Backfill existing rows in one statement (gen_random_uuid from pgcrypto, which
    # Active Storage already relies on in this app). Small table pre-beta.
    execute <<~SQL.squish
      UPDATE profile_photos
      SET public_id = gen_random_uuid()
      WHERE public_id IS NULL
    SQL

    change_column_null :profile_photos, :public_id, false
    add_index :profile_photos, :public_id, unique: true
  end

  def down
    remove_index :profile_photos, :public_id
    remove_column :profile_photos, :public_id
  end
end
