# frozen_string_literal: true

module Date9ja
  module Snapshot
    # Runs the shared canonical Date9ja source-schema signature (v2) against the
    # scratch snapshot before any row is read. The SQL lives in
    # `scripts/date9ja/schema_signature.sql` (Date9ja source-adapter tooling) and
    # RAISEs on any structural drift; here that surfaces as SchemaDriftError.
    module SchemaGuard
      SCRIPT_PATH = Rails.root.join("scripts/date9ja/schema_signature.sql")

      class SchemaDriftError < StandardError; end

      module_function

      def verify!(connection:, script_path: SCRIPT_PATH)
        connection.execute(File.read(script_path))
        true
      rescue ActiveRecord::StatementInvalid => e
        # The signature block RAISEs a message that is structural only (table
        # names, counts, a hex digest) — no row data — but scrub to a single
        # line defensively.
        raise SchemaDriftError, e.message.to_s.split("\n").first.to_s.strip
      end
    end
  end
end
