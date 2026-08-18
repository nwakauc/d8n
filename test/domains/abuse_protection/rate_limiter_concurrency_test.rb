require "test_helper"

module AbuseProtection
  # Proves the limiter is a correct source of truth when many requests for the
  # same identity contend at once — the exact condition that a naive process-local
  # counter would get wrong under multiple Puma workers / app nodes. The atomic
  # INSERT ... ON CONFLICT DO UPDATE means N increments produce exactly N, never
  # fewer, so a limit cannot be exceeded by racing.
  #
  # Threads are capped at the test connection pool; each does many iterations, so
  # several upserts genuinely contend on the same row throughout the run.
  class RateLimiterConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    THREADS = 4
    PER_THREAD = 25

    test "concurrent increments on one bucket are counted exactly once each" do
      window = Time.zone.at(0)
      expires = 1.hour.from_now
      results = Queue.new
      start = Queue.new

      threads = THREADS.times.map do
        Thread.new do
          start.pop
          PER_THREAD.times do
            ActiveRecord::Base.connection_pool.with_connection do
              results << RateLimitCounter.increment!(throttle_key: "race", window_started_at: window, expires_at: expires)
            end
          rescue StandardError => e
            results << e
          end
        end
      end
      THREADS.times { start << true }
      threads.each(&:join)

      total = THREADS * PER_THREAD
      counts = total.times.map { results.pop }
      errors = counts.select { |c| c.is_a?(StandardError) }
      assert_empty errors, errors.map(&:inspect).join("\n")
      # Every increment returned a distinct value 1..total (no lost updates), and
      # the final stored count is exactly total.
      assert_equal (1..total).to_a, counts.sort
      assert_equal total, RateLimitCounter.find_by(throttle_key: "race", window_started_at: window).count
    ensure
      RateLimitCounter.where(throttle_key: "race").delete_all
    end

    test "a limit of N cannot be exceeded by concurrent callers" do
      window = Time.zone.at(100)
      expires = 1.hour.from_now
      hard_limit = 10
      results = Queue.new
      start = Queue.new

      threads = THREADS.times.map do
        Thread.new do
          start.pop
          PER_THREAD.times do
            ActiveRecord::Base.connection_pool.with_connection do
              count = RateLimitCounter.increment!(throttle_key: "cap", window_started_at: window, expires_at: expires)
              results << (count <= hard_limit)
            end
          end
        end
      end
      THREADS.times { start << true }
      threads.each(&:join)

      in_limit = (THREADS * PER_THREAD).times.count { results.pop }
      assert_equal hard_limit, in_limit, "exactly #{hard_limit} callers should observe an in-limit count"
    ensure
      RateLimitCounter.where(throttle_key: "cap").delete_all
    end
  end
end
