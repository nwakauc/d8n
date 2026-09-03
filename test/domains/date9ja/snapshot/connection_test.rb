# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Snapshot
    class ConnectionTest < ActiveSupport::TestCase
      Unsafe = Connection::UnsafeConfiguration

      test "accepts an explicit scratch snapshot URL" do
        assert Connection.assert_safe!("postgres://localhost:5432/date9ja_snapshot_sanitized")
      end

      test "rejects a missing URL" do
        assert_raises(Unsafe) { Connection.assert_safe!(nil) }
        assert_raises(Unsafe) { Connection.assert_safe!("   ") }
      end

      test "rejects a non-postgresql URL" do
        assert_raises(Unsafe) { Connection.assert_safe!("mysql://localhost/date9ja_snapshot") }
      end

      test "rejects a URL that does not name a database" do
        assert_raises(Unsafe) { Connection.assert_safe!("postgres://localhost:5432/") }
      end

      test "rejects production-looking names and hosts" do
        assert_raises(Unsafe) { Connection.assert_safe!("postgres://localhost/date9ja_production") }
        assert_raises(Unsafe) { Connection.assert_safe!("postgres://db.prod.internal/date9ja_snapshot") }
        assert_raises(Unsafe) { Connection.assert_safe!("postgres://localhost/date9ja_live") }
      end

      test "rejects target overrides hidden in PostgreSQL query parameters" do
        assert_raises(Unsafe) { Connection.assert_safe!("postgres://safe/date9ja_snapshot?dbname=d8n_production") }
        assert_raises(Unsafe) { Connection.assert_safe!("postgres://safe/date9ja_snapshot?host=prod.internal") }
        assert_raises(Unsafe) { Connection.assert_safe!("postgres:///date9ja_snapshot?service=production") }
      end

      test "decodes target components before applying production-name checks" do
        assert_raises(Unsafe) { Connection.assert_safe!("postgres://localhost/date9ja_%70roduction") }
        assert_raises(Unsafe) { Connection.assert_safe!("postgres://db.%70rod.internal/date9ja_snapshot") }
      end

      test "rejects an invalid URL" do
        assert_raises(Unsafe) { Connection.assert_safe!("::not a url::") }
      end
    end
  end
end
