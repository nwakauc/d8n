# frozen_string_literal: true

module Date9ja
  module Import
    # Deterministic, PII-free tally for one profile-photo PASS-2 byte-transfer run
    # (MEDIA-TRANSFER.md §15). Every source Photo row gets exactly one terminal
    # disposition; `photos_considered == sum(dispositions)` always holds.
    #
    # Every non-terminal-success disposition is ALSO counted as
    # `unexplained_failure`; cutover requires `unexplained_failures == 0`.
    # A reviewed-exception workflow is NOT implemented in this build — the
    # `reviewed_exceptions` measure is present for the cutover-gate formula and
    # stays 0.
    #
    # `to_h` is counts + reason codes + aggregate measures only — no storage key,
    # filename, checksum value, email, name, or any per-row id.
    class PhotoTransferReconciliation
      SUCCESS_DISPOSITIONS = %i[transferred already_transferred].freeze

      DISPOSITIONS = %i[
        transferred
        already_transferred
        owner_not_imported
        source_unavailable
        source_changed
        validation_failed
        destination_failed
        binding_conflict
        processing_failed
        quarantined
        explicitly_skipped
      ].freeze

      REASON_CODES = %w[
        owner_not_imported
        missing_preflight
        source_object_missing
        source_object_unavailable
        source_transport_refused
        preflight_failed
        source_size_mismatch
        source_checksum_mismatch
        content_type_drift
        oversize
        not_an_image
        unsupported_content_type
        malformed_image
        remote_orphan
        destination_collision
        mapping_drift
        binding_immutable
        chain_mismatch
        capacity_exceeded
        moderation_unmapped
        multiple_primary
        record_invalid
        processing_failed
        processing_drain_timeout
        transfer_error
      ].freeze

      MEASURES = %i[
        total_source_photos
        owners_ordered owners_one_primary owners_zero_primary owners_multiple_primary_quarantined
        owners_flagged_for_review
        moderation_pending moderation_approved moderation_rejected
        destination_uploads_created destination_uploads_reused
        destination_orphan_blobs_recovered destination_remote_orphans destination_collisions
        profile_photos_created profile_photos_reused reference_map_bindings_created
        processing_enqueued processing_succeeded processing_failed
        mapping_drift
        binding_conflicts
        unexplained_failures reviewed_exceptions
      ].freeze

      def initialize
        @counts = Hash.new(0)
        @reasons = Hash.new(0)
        @measures = Hash.new(0)
      end

      def considered = bump(:photos_considered)

      def disposition!(name, reason: nil)
        raise ArgumentError, "unknown disposition #{name}" unless DISPOSITIONS.include?(name)

        bump(name)
        note!(reason) if reason
        measure!(:unexplained_failures) unless SUCCESS_DISPOSITIONS.include?(name)
      end

      def note!(reason_code)
        raise ArgumentError, "unknown reason code #{reason_code.inspect}" unless REASON_CODES.include?(reason_code)

        @reasons[reason_code] += 1
      end

      def measure!(name, value = 1, mode: :increment)
        raise ArgumentError, "unknown measure #{name}" unless MEASURES.include?(name)

        case mode
        when :set then @measures[name] = value
        when :increment then @measures[name] += value
        else raise ArgumentError, "unknown measure mode #{mode.inspect}"
        end
      end

      def count(name) = @counts[name]
      def reason_count(code) = @reasons[code]
      def measure(name) = @measures[name]

      def balanced?
        @counts[:photos_considered] == DISPOSITIONS.sum { |d| @counts[d] }
      end

      def cutover_ready?
        balanced? && @measures[:unexplained_failures].zero?
      end

      def to_h
        {
          "photos_considered" => @counts[:photos_considered],
          "balanced" => balanced?,
          "cutover_ready" => cutover_ready?,
          "dispositions" => DISPOSITIONS.to_h { |d| [ d.to_s, @counts[d] ] },
          "measures" => MEASURES.to_h { |m| [ m.to_s, @measures[m] ] },
          "reason_codes" => REASON_CODES.to_h { |c| [ c, @reasons[c] ] }.select { |_, n| n.positive? }
        }
      end

      private

      def bump(name) = @counts[name] += 1
    end
  end
end
