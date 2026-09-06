# frozen_string_literal: true

module Date9ja
  module Import
    # Deterministic, machine-readable, PII-free tally for one profile &
    # preference import run.
    #
    # Same contract as the identity importer's Reconciliation: every source row
    # lands in EXACTLY ONE disposition and every non-import carries a reason
    # code, so `source_users_considered == sum(dispositions)` always holds and
    # nothing is lost unexplained.
    #
    # `notes` is deliberately separate from dispositions. A row can be imported
    # successfully and still leave a field unset — because the member never
    # answered it, or because its legacy code has no approved D8N destination
    # yet. That is a partial import, not a failure, and it must not be counted
    # as one. Notes say what was left unset and why.
    class ProfilePreferenceReconciliation
      DISPOSITIONS = %i[imported already_imported skipped failed].freeze

      CREATION_COUNTERS = %i[
        preferences_created option_selections_created genders_decoded
        legacy_references_created
      ].freeze

      ANOMALY_COUNTERS = %i[binding_conflicts malformed_rows].freeze

      REASON_CODES = %w[
        source_soft_deleted
        source_banned
        profile_not_imported
        already_imported
        dangling_binding
        binding_conflict
        preference_invalid
        option_selection_invalid
        approved_option_group_missing
        approved_option_missing
        source_row_error
      ].freeze

      # Why a field was left unset on an otherwise successful import. `absent`
      # = the member never answered. `unmapped` = the legacy code is real but
      # has no approved D8N destination (an open decision, not a data problem).
      NOTE_CODES = %w[
        interested_in_absent
        interested_in_unmapped
        gender_absent
        gender_unmapped
        age_range_absent
        age_range_partial
        age_range_invalid
        max_distance_km_no_source
        meeting_pace_no_source
        relationship_intent_absent
        relationship_intent_unmapped
        has_children_absent
        wants_children_absent
        wants_children_unmapped
      ].freeze

      def initialize
        @counts = Hash.new(0)
        @reasons = Hash.new(0)
        @notes = Hash.new(0)
      end

      def considered = bump(:source_users_considered)

      def imported!(**created)
        bump(:eligible)
        bump(:imported)
        created.each { |counter, n| add(counter, n) }
      end

      def already_imported!
        bump(:eligible)
        bump(:already_imported)
        reason("already_imported")
      end

      def skipped!(code)
        bump(:skipped)
        reason(code)
      end

      def failed!(code)
        bump(:failed)
        reason(code)
      end

      # An already-imported row can still have had its gender decoded (a prior
      # run bound the preference before this decode existed).
      def decoded_gender! = bump(:genders_decoded)

      def note!(code)
        raise ArgumentError, "unknown note #{code}" unless NOTE_CODES.include?(code.to_s)

        @notes[code.to_s] += 1
      end

      def anomaly!(counter)
        raise ArgumentError, "unknown anomaly #{counter}" unless ANOMALY_COUNTERS.include?(counter)

        bump(counter)
      end

      def count(counter) = @counts[counter]

      def reason_count(code) = @reasons[code.to_s]

      def note_count(code) = @notes[code.to_s]

      # True when every considered row landed in exactly one disposition.
      def balanced?
        @counts[:source_users_considered] == DISPOSITIONS.sum { |d| @counts[d] }
      end

      def to_h
        {
          "source_users_considered" => @counts[:source_users_considered],
          "dispositions" => DISPOSITIONS.to_h { |d| [ d.to_s, @counts[d] ] },
          "eligible" => @counts[:eligible],
          "created" => CREATION_COUNTERS.to_h { |c| [ c.to_s, @counts[c] ] },
          "anomalies" => ANOMALY_COUNTERS.to_h { |c| [ c.to_s, @counts[c] ] },
          "reasons" => @reasons.dup,
          "notes" => @notes.dup,
          "balanced" => balanced?
        }
      end

      private

      def reason(code)
        raise ArgumentError, "unknown reason #{code}" unless REASON_CODES.include?(code.to_s)

        @reasons[code.to_s] += 1
      end

      def bump(counter) = @counts[counter] += 1

      def add(counter, n) = @counts[counter] += n
    end
  end
end
