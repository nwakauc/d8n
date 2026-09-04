# frozen_string_literal: true

module Date9ja
  module Import
    # Deterministic, PII-free tally for one profile-video migration run (ADR 0029).
    #
    # Two stages share this vocabulary:
    #   :adopt  — Pass 2A. Maximum success = a verified, duration-accepted
    #             destination ORIGINAL blob (SOURCE_ACCEPTED / DESTINATION_ADOPTED).
    #             Never `transferred`.
    #   :domain — Pass 2B. Maximum success = a fully migrated ProfileVideo:
    #             exact owner + exact original attachment + exact ReferenceMap
    #             binding + processing + validated playback + validated poster +
    #             ready + existing raw-purge behaviour.
    #
    # Every source ProfileVideo row gets exactly one terminal disposition; the
    # invariant `videos_considered == sum(dispositions)` always holds. `to_h` is
    # counts + reason codes + aggregate measures only — no storage key, filename,
    # checksum value, source URL, email, name, or any per-row id.
    class VideoTransferReconciliation
      SUCCESS_DISPOSITIONS = %i[
        destination_adopted already_destination_adopted ready already_ready
      ].freeze

      DISPOSITIONS = %i[
        destination_adopted
        already_destination_adopted
        ready
        already_ready
        owner_not_imported
        source_unavailable
        source_changed
        validation_failed
        quarantined
        destination_failed
        binding_conflict
        processing_failed
        derivative_validation_failed
        explicitly_skipped
      ].freeze

      REASON_CODES = %w[
        owner_not_imported
        owner_wrong_brand
        owner_conflict
        missing_preflight
        multiple_videos_per_owner
        source_object_missing
        source_object_unavailable
        source_transport_refused
        preflight_failed
        source_size_mismatch
        source_checksum_mismatch
        content_type_drift
        oversize
        not_a_video
        unsupported_content_type
        malformed_container
        duration_unreadable
        duration_over_limit
        remote_orphan
        destination_collision
        moderation_unmapped
        transfer_error
        pass2a_blob_missing
        pass2a_key_mismatch
        pass2a_blob_size_mismatch
        pass2a_blob_checksum_mismatch
        pass2a_blob_content_type_mismatch
        conflicting_profile_video
        conflicting_binding
        one_video_invariant
        attachment_mismatch
        chain_mismatch
        binding_immutable
        mapping_drift
        record_invalid
        playback_invalid
        poster_invalid
        processing_job_failed
        processing_drain_timeout
        processing_claim_conflict
      ].freeze

      MEASURES = %i[
        total_source_videos
        owners_considered owner_not_imported
        moderation_pending moderation_approved moderation_rejected
        content_type_mp4 content_type_quicktime
        destination_uploads_created destination_uploads_reused
        duration_derived duration_within_limit duration_over_limit duration_unreadable
        container_invalid
        source_changed
        destination_failures
        binding_conflicts destination_remote_orphans destination_collisions
        profile_videos_created profile_videos_reused
        reference_map_bindings_created reference_map_bindings_reused
        processing_attempts processing_succeeded processing_failures
        playback_validated poster_validated
        ready already_ready originals_purged
        domain_resume_recoveries processing_stale_reclaims
        unexplained_failures reviewed_exceptions
      ].freeze

      def initialize(stage: :adopt)
        @stage = stage
        @counts = Hash.new(0)
        @reasons = Hash.new(0)
        @measures = Hash.new(0)
      end

      def considered = bump(:videos_considered)

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
        @counts[:videos_considered] == DISPOSITIONS.sum { |d| @counts[d] }
      end

      # A run being clean is not cutover readiness. Cutover remains gated at
      # Pass 2C (synthetic L2) and later migration gates.
      def clean?
        balanced? && @measures[:unexplained_failures].zero?
      end
      alias_method :phase_a_clean?, :clean? # retained Pass-2A name

      def lifecycle
        case @stage
        when :domain
          "PROFILE_VIDEO_DOMAIN_MIGRATED (pass 2B) — ProfileVideo + attachment + " \
            "ReferenceMap + processing + playback + poster + ready + purge"
        else
          "SOURCE_ACCEPTED / DESTINATION_ADOPTED (pass 2A; NOT transferred)"
        end
      end

      def to_h
        {
          "videos_considered" => @counts[:videos_considered],
          "stage" => @stage.to_s,
          "balanced" => balanced?,
          "clean" => clean?,
          "phase_a_clean" => clean?, # retained Pass-2A key
          "lifecycle" => lifecycle,
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
