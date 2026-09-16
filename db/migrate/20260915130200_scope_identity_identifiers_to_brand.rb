class ScopeIdentityIdentifiersToBrand < ActiveRecord::Migration[8.0]
  def up
    change_column_null :identity_identifiers, :brand_id, false

    # Add the new brand-scoped unique index BEFORE dropping the old global
    # one, so there is never a window with no uniqueness enforcement at all.
    add_index :identity_identifiers, [ :brand_id, :kind, :normalized_value ],
      unique: true, where: "deleted_at IS NULL",
      name: "index_identity_identifiers_on_brand_kind_and_normalized_value"

    remove_index :identity_identifiers, [ :kind, :normalized_value ],
      name: "index_identity_identifiers_on_kind_and_normalized_value"
  end

  def down
    add_index :identity_identifiers, [ :kind, :normalized_value ],
      unique: true, where: "deleted_at IS NULL",
      name: "index_identity_identifiers_on_kind_and_normalized_value"

    remove_index :identity_identifiers, [ :brand_id, :kind, :normalized_value ],
      name: "index_identity_identifiers_on_brand_kind_and_normalized_value"

    change_column_null :identity_identifiers, :brand_id, true
  end
end
