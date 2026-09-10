# frozen_string_literal: true

module Date9ja
  module Snapshot
    # A SEPARATE, deliberately narrow reader over the sensitive Date9ja `users`
    # fields — religion / tribe / ethnicity / denomination / genotype /
    # state_of_origin / nationality / is_nigerian / the openness flags / the
    # matching-preference arrays / interest_in_nigerian_culture.
    #
    # WHY IT IS SEPARATE. The main `UserSource` firewalls these columns out by
    # design (FieldMapping::SENSITIVE_DENYLIST) so an ordinary import can never
    # touch them. Preserving them is now in scope, but through its OWN adapter,
    # its OWN record type, and its OWN importer (`SensitiveProfileImport`) so the
    # boundary stays auditable: this is the only place these columns are read.
    #
    # In the sanitized rehearsal snapshot every value here is NULL / '{}' (the
    # sanitizer minimises them — SANITIZATION-CONTRACT R1). This adapter still
    # runs; it simply yields all-absent records. Real values only appear on a
    # pristine/cutover snapshot, and only after the privacy-safe source
    # classification (source_census.sql sensitive measures) has been reviewed.
    class SensitiveUserSource
      include Enumerable

      # Keep this projection explicit. `genotype` is not a Date9ja column: the
      # source stores it inside the bounded `v2_onboarding_answers` JSON object.
      # Date9ja has never had preferred_ethnicity/preferred_genotype columns;
      # typed NULL arrays preserve the record contract without pretending those
      # concepts exist in the source schema.
      SELECTED_EXPRESSIONS = [
        "id", "deleted_at", "banned_at",
        "is_nigerian", "state_of_origin", "nationality", "tribe", "ethnicity", "religion", "denomination",
        "v2_onboarding_answers ->> 'genotype' AS genotype",
        # The rest of the bounded V2 questionnaire object (faith_practice,
        # family_involvement, language_at_home, settlement, money_providing,
        # children, lifestyle, conflict, custom_religion, ...). Genotype is
        # removed here because it has its own gated destination and DPIA review;
        # the remainder is preserved verbatim into owner-only profile metadata
        # (audit blocker ledger item 7) rather than dropped.
        "(v2_onboarding_answers - 'genotype') AS v2_onboarding_answers",
        "intertribal_marriage_openness", "polygamy_openness", "interest_in_nigerian_culture",
        "preferred_religion", "preferred_tribes",
        "NULL::character varying[] AS preferred_ethnicity",
        "NULL::character varying[] AS preferred_genotype"
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
          @connection.exec_query("SELECT #{SELECTED_EXPRESSIONS.join(', ')} FROM users ORDER BY id").to_a
        end
      end
    end
  end
end
