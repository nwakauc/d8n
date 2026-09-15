class AddBrandIdToIdentityIdentifiers < ActiveRecord::Migration[8.0]
  def change
    # Nullable for now -- backfilled in the next migration, then locked
    # NOT NULL in the migration after that. Purely additive; no application
    # code reads this column yet, so this is safe to deploy standalone.
    add_reference :identity_identifiers, :brand, foreign_key: true, index: true
  end
end
