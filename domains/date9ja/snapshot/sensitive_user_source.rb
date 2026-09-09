# frozen_string_literal: true

module Date9ja
  module Snapshot
    # A SEPARATE, deliberately narrow reader over the sensitive Date9ja `users`
    # columns — religion / tribe / ethnicity / denomination / genotype /
    # state_of_origin / nationality / is_nigerian / the openness flags / the
    # matching-preference arrays / interest_in_nigerian_culture.
    #
    # WHY IT IS SEPARATE. The main `UserSource` firewalls these columns out by
    # design (FieldMapping::SENSITIVE_DENYLIST) so an ordinary import can never
    # touch them. Preserving them is now in scope, but through its OWN adapter,
    # its OWN record type, and its OWN importer (`SensitiveProfileImport`) so the
    # boundary stays auditable: this is the only place these columns are read.
    #
    # In the sanitized rehearsal snapshot every column here is NULL / '{}' (the
    # sanitizer minimises them — SANITIZATION-CONTRACT R1). This adapter still
    # runs; it simply yields all-absent records. Real values only appear on a
    # pristine/cutover snapshot, and only after the privacy-safe source
    # classification (source_census.sql sensitive measures) has been reviewed.
    class SensitiveUserSource
      include Enumerable

      SELECTED_COLUMNS = %w[
        id deleted_at banned_at
        is_nigerian state_of_origin nationality tribe ethnicity religion denomination
        genotype intertribal_marriage_openness polygamy_openness interest_in_nigerian_culture
        preferred_religion preferred_tribes preferred_ethnicity preferred_genotype
      ].freeze

      def initialize(rows: nil, connection: nil, verify_schema: true)
        raise ArgumentError, "provide rows: or connection:" if rows.nil? && connection.nil?

        @rows = rows
        @connection = connection
        @verify_schema = verify_schema
      end

      def each
        return enum_for(:each) unless block_given?

        SchemaGuard.verify!(connection: @connection) if @connection && @verify_schema
        raw_rows.each { |raw| yield SensitiveUserRecord.from_raw(raw) }
      end

      private

      def raw_rows
        if @rows
          @rows.map { |row| row.transform_keys(&:to_s) }.sort_by { |row| row.fetch("id").to_i }
        else
          @connection.exec_query("SELECT #{SELECTED_COLUMNS.join(', ')} FROM users ORDER BY id").to_a
        end
      end
    end
  end
end
