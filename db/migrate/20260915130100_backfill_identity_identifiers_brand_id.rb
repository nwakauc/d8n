class BackfillIdentityIdentifiersBrandId < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE identity_identifiers ii
      SET brand_id = bm.brand_id
      FROM brand_memberships bm
      WHERE bm.user_id = ii.user_id
        AND ii.brand_id IS NULL
        AND bm.deleted_at IS NULL
    SQL

    # Fail loudly if any row is left unresolved (e.g. a user with zero or
    # more than one brand_membership) rather than silently shipping an
    # ambiguous/NULL brand_id forward.
    unresolved = execute("SELECT count(*) FROM identity_identifiers WHERE brand_id IS NULL").first["count"].to_i
    raise "#{unresolved} identity_identifiers rows have no resolvable brand_id -- aborting" if unresolved.positive?
  end

  def down
    execute "UPDATE identity_identifiers SET brand_id = NULL"
  end
end
