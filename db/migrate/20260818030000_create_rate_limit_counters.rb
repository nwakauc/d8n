class CreateRateLimitCounters < ActiveRecord::Migration[8.1]
  # Generic fixed-window counter store for D8N abuse protection. One row per
  # (throttle_key, window bucket); the key is an opaque HMAC of
  # brand/identity/action/rule so no raw IP, user id, or product content is
  # persisted. Rows carry an `expires_at` so a recurring purge keeps storage
  # bounded and key cardinality from growing without limit.
  def change
    create_table :rate_limit_counters do |t|
      t.string :throttle_key, null: false
      t.datetime :window_started_at, null: false
      t.datetime :expires_at, null: false
      t.integer :count, default: 0, null: false

      t.timestamps
    end

    # Atomic INSERT ... ON CONFLICT DO UPDATE targets this unique bucket, so the
    # increment is race-free across threads, processes, and app nodes.
    add_index :rate_limit_counters, [ :throttle_key, :window_started_at ],
      unique: true, name: "idx_rate_limit_counters_bucket"
    # Drives the bounded-storage purge of lapsed windows.
    add_index :rate_limit_counters, :expires_at, name: "idx_rate_limit_counters_expiry"

    add_check_constraint :rate_limit_counters, "count >= 0", name: "chk_rate_limit_counters_count"
  end
end
