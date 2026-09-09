# frozen_string_literal: true

module Date9ja
  module Import
    # Deterministic, PII-free tally for one sensitive-profile import run. Same
    # contract as the other reconciliations: every considered row lands in
    # exactly one disposition; a field left unset on an otherwise successful row
    # is a NOTE, not a failure.
    class SensitiveProfileReconciliation
      DISPOSITIONS = %i[imported skipped failed].freeze

      CREATION_COUNTERS = %i[
        scalars_written option_selections_created preference_attributes_written
      ].freeze

      REASON_CODES = %w[
        source_soft_deleted source_banned profile_not_imported
        sensitive_write_invalid source_row_error
      ].freeze

      FIELDS = %w[
        is_nigerian state_of_origin nationality interest_in_nigerian_culture
        tribe ethnicity religion denomination genotype
        intertribal_marriage_openness polygamy_openness
        preferred_religion preferred_tribes preferred_ethnicity preferred_genotype
      ].freeze

      # Per field: _absent (member never answered), _unmapped (real value, no
      # reviewed D8N destination code yet — quarantined), _mapped (written),
      # _preserved (a member/operator/earlier value already held — left alone).
      NOTE_CODES = FIELDS.flat_map { |f| %W[#{f}_absent #{f}_unmapped #{f}_mapped #{f}_preserved #{f}_partial] }.freeze

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

      def skipped!(code)
        bump(:skipped)
        reason(code)
      end

      def failed!(code)
        bump(:failed)
        reason(code)
      end

      def note!(code)
        raise ArgumentError, "unknown note #{code}" unless NOTE_CODES.include?(code.to_s)

        @notes[code.to_s] += 1
      end

      def count(counter) = @counts[counter]
      def reason_count(code) = @reasons[code.to_s]
      def note_count(code) = @notes[code.to_s]

      def balanced?
        @counts[:source_users_considered] == DISPOSITIONS.sum { |d| @counts[d] }
      end

      def to_h
        {
          "source_users_considered" => @counts[:source_users_considered],
          "dispositions" => DISPOSITIONS.to_h { |d| [ d.to_s, @counts[d] ] },
          "eligible" => @counts[:eligible],
          "created" => CREATION_COUNTERS.to_h { |c| [ c.to_s, @counts[c] ] },
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
