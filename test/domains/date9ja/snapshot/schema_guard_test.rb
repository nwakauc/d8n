# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Snapshot
    class SchemaGuardTest < ActiveSupport::TestCase
      FakeConnection = Struct.new(:behaviour) do
        def execute(_sql)
          case behaviour
          when :ok then true
          when :drift
            raise ActiveRecord::StatementInvalid,
              "PG::RaiseException: ERROR:  SCHEMA DRIFT: expected 51 public base tables, found 52\nCONTEXT: ..."
          end
        end
      end

      test "passes when the signature block runs without raising" do
        assert SchemaGuard.verify!(connection: FakeConnection.new(:ok))
      end

      test "raises SchemaDriftError (single line) on any drift" do
        error = assert_raises(SchemaGuard::SchemaDriftError) do
          SchemaGuard.verify!(connection: FakeConnection.new(:drift))
        end

        assert_includes error.message, "SCHEMA DRIFT"
        refute_includes error.message, "\n"
      end

      test "runs the real shared signature script against this test database" do
        # The D8N schema is not the Date9ja schema, so the shared guard must
        # abort here — proving the script is wired and fails closed.
        assert_raises(SchemaGuard::SchemaDriftError) do
          SchemaGuard.verify!(connection: ActiveRecord::Base.connection)
        end
      end
    end
  end
end
