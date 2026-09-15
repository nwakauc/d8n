class CreateAdminIdentityCorrections < ActiveRecord::Migration[8.0]
  def change
    # Full history of admin-applied corrections to a member's canonical
    # identity/marketplace fields (gender on Profile, interested_in on
    # ProfilePreference today). Every row is additive -- corrections are never
    # edited or deleted, so "who changed what, from what, to what, and why" is
    # always reconstructible, distinct from the corrected record's current
    # value.
    create_table :admin_identity_corrections do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :field, null: false
      t.jsonb :previous_value, null: false, default: {}
      t.jsonb :new_value, null: false, default: {}
      t.text :reason, null: false
      t.text :note

      t.timestamps
    end

    add_index :admin_identity_corrections, [ :brand_id, :profile_id ]
  end
end
