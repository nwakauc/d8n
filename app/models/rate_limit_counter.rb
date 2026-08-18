class RateLimitCounter < ApplicationRecord
  # Atomically increments the fixed-window bucket for a throttle key and returns
  # the new count. A single INSERT ... ON CONFLICT DO UPDATE is atomic at the row
  # level, so concurrent requests targeting the same (key, window) — across
  # threads, Puma workers, and horizontally-scaled app nodes — can never lose an
  # increment or slip past the limit through a read-modify-write race. This is the
  # multi-node source of truth: Postgres, not any process-local memory.
  INCREMENT_SQL = <<~SQL.squish.freeze
    INSERT INTO rate_limit_counters
      (throttle_key, window_started_at, expires_at, count, created_at, updated_at)
    VALUES (?, ?, ?, 1, ?, ?)
    ON CONFLICT (throttle_key, window_started_at)
    DO UPDATE SET count = rate_limit_counters.count + 1, updated_at = EXCLUDED.updated_at
    RETURNING count
  SQL

  def self.increment!(throttle_key:, window_started_at:, expires_at:, now: Time.current)
    sql = sanitize_sql_array([ INCREMENT_SQL, throttle_key, window_started_at, expires_at, now, now ])
    result = connection.exec_query(sql, "RateLimitCounter Increment")
    Integer(result.first.fetch("count"))
  end

  # Deletes lapsed windows in bounded batches so the table cannot grow without
  # limit. Best-effort cleanup — liveness of the limiter never depends on it,
  # because a lapsed bucket simply stops being consulted once the window rolls.
  def self.purge_expired(now: Time.current, batch_size: 5_000)
    where(expires_at: ..now).in_batches(of: batch_size).delete_all
  end
end
