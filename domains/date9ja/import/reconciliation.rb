# frozen_string_literal: true

module Date9ja
  module Import
    # Deterministic, machine-readable, PII-free tally for one identity-import run.
    # Every source row lands in exactly one disposition (imported / already /
    # skipped / failed) and every non-import carries a reason code — no
    # unexplained loss. `to_h` contains counts and reason codes only: no email,
    # phone, hash, or free-text ever passes through here.
    class Reconciliation
      DISPOSITIONS = %i[imported already_imported skipped failed].freeze

      CREATION_COUNTERS = %i[
        users_created identifiers_created credentials_created
        password_hashes_created memberships_created profiles_created
        legacy_references_created
      ].freeze

      ANOMALY_COUNTERS = %i[
        normalization_collisions missing_identifiers malformed_rows binding_conflicts
      ].freeze

      REASON_CODES = %w[
        source_soft_deleted
        source_banned
        already_imported
        email_unparseable
        email_collision
        phone_unparseable
        phone_collision
        credential_hash_unusable
        profile_invalid
        dangling_binding
        incomplete_binding
        binding_conflict
        source_row_error
      ].freeze

      def initialize
        @counts = Hash.new(0)
        @reasons = Hash.new(0)
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

      def skipped!(reason_code)
        bump(:skipped)
        reason(reason_code)
      end

      def failed!(reason_code)
        bump(:failed)
        reason(reason_code)
      end

      # Record a reason code without changing the row's disposition (used for
      # optional-identifier notes like an unparseable phone on an otherwise
      # imported row).
      def note!(reason_code)
        reason(reason_code)
      end

      def anomaly!(counter)
        raise ArgumentError, "unknown anomaly #{counter}" unless ANOMALY_COUNTERS.include?(counter)

        bump(counter)
      end

      def count(counter) = @counts[counter]

      def reason_count(code) = @reasons[code]

      def to_h
        {
          "source_users_considered" => @counts[:source_users_considered],
          "dispositions" => DISPOSITIONS.to_h { |d| [ d.to_s, @counts[d] ] },
          "eligible" => @counts[:eligible],
          "created" => CREATION_COUNTERS.to_h { |c| [ c.to_s, @counts[c] ] },
          "anomalies" => ANOMALY_COUNTERS.to_h { |c| [ c.to_s, @counts[c] ] },
          "reason_codes" => REASON_CODES.to_h { |code| [ code, @reasons[code] ] }
            .select { |_, n| n.positive? }
        }
      end

      private

      def bump(counter) = @counts[counter] += 1

      def add(counter, n) = @counts[counter] += n

      def reason(code)
        raise ArgumentError, "unknown reason code #{code.inspect}" unless REASON_CODES.include?(code)

        @reasons[code] += 1
      end
    end
  end
end
