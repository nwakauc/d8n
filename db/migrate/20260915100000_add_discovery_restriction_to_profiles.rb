class AddDiscoveryRestrictionToProfiles < ActiveRecord::Migration[8.0]
  def change
    # Moderator "hide from discovery without suspend/ban" (mirrors Date9ja's own
    # discovery_restricted_at/reason/note/restricted_by columns). Distinct from
    # profiles.status/visibility (account lifecycle / member pause / incomplete)
    # and from account_enforcements (suspension/ban, which also locks the account
    # and revokes sessions) -- a restricted member stays logged in and active,
    # just excluded from discovery/direct profile view by other members.
    add_column :profiles, :discovery_restricted_at, :datetime
    add_column :profiles, :discovery_restriction_reason, :string
    add_column :profiles, :discovery_restriction_note, :text
    add_reference :profiles, :discovery_restricted_by_admin_user, foreign_key: { to_table: :admin_users }, index: true

    add_index :profiles, :discovery_restricted_at
  end
end
