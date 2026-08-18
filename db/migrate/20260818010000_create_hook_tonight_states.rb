class CreateHookTonightStates < ActiveRecord::Migration[8.0]
  # A HookUs "Hook Tonight" state: a member's TEMPORARY "I'm available/open to
  # meeting tonight" availability, expressed so they surface in the Hook Tonight
  # discovery pool. This is intent/availability only — it never creates a Match,
  # Conversation, or Message. Approaching someone found here still goes through the
  # existing 🔥 Hook flow (see ADR 0015); Hook Tonight does not get its own
  # messaging mechanism.
  #
  # Correctness never depends on a sweeper: HookTonightState#live? (and the `live`
  # scope) re-check `expires_at` against the clock and require `deactivated_at` to
  # be null, so a stale/deactivated row can never make someone appear available.
  #
  # Exactly ONE current-state row per (brand, profile) — repeated activate/
  # deactivate toggling reuses this single row via an upsert rather than growing
  # unbounded history. The unique index enforces that invariant at the data layer,
  # including under concurrent double-activation (Postgres ON CONFLICT).
  def change
    create_table :hook_tonight_states do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: false
      # V1 carries a single intent ("open_to_meeting"); the column is the seam for
      # future availability nuance without a schema change or a questionnaire.
      t.string :intent, null: false, default: "open_to_meeting"
      t.datetime :activated_at, null: false
      t.datetime :expires_at, null: false
      # Set when the member manually turns Hook Tonight off; nil while active.
      # Distinct from lapse (expires_at) so activation vs. deactivation stays
      # auditable and so `live` can exclude a just-deactivated row immediately.
      t.datetime :deactivated_at

      t.timestamps
    end

    # One current-state row per member: blocks duplicate activation (including
    # concurrent) and keeps toggling from growing history. Also the discovery
    # lookup index (brand + membership).
    add_index :hook_tonight_states, [ :brand_id, :profile_id ],
      unique: true, name: "index_hook_tonight_states_on_brand_and_profile"
    # Live-pool scan: newest-expiring live rows for a brand.
    add_index :hook_tonight_states, [ :brand_id, :expires_at ],
      name: "idx_hook_tonight_states_live"
    add_index :hook_tonight_states, [ :id, :brand_id ],
      unique: true, name: "idx_hook_tonight_states_on_id_brand"

    # Tenant-safe composite foreign key: a state can only reference a profile
    # within its own brand.
    add_foreign_key :hook_tonight_states, :profiles,
      column: [ :profile_id, :brand_id ], primary_key: [ :id, :brand_id ],
      name: "fk_hook_tonight_states_profile_tenant"
  end
end
