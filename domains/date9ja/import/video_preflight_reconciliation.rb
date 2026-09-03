# frozen_string_literal: true

module Date9ja
  module Import
    # Deterministic, PII-free tally for one profile-video PASS-1 preflight run.
    #
    # Every source ProfileVideo row gets exactly one terminal disposition; the
    # invariant
    #   videos_considered == sum(dispositions)
    # always holds. `to_h` is counts + reason codes + aggregate measures only —
    # no storage key, filename, checksum value, email, name, or any per-row id.
    #
    # Duration is MEASURED ONLY. Pass 1 never rejects a structurally valid row
    # for being over the current D8N limit — the grandfather / trim / quarantine
    # decision is a pass-2 product decision (DECISIONS.md).
    class VideoPreflightReconciliation
      # Mutually exclusive terminal dispositions.
      DISPOSITIONS = %i[
        preflighted
        already_preflighted
        owner_not_imported
        unavailable
        malformed
        failed
        explicitly_skipped
      ].freeze

      CREATION_COUNTERS = %i[media_object_refs_created media_attachment_refs_created].freeze

      # Aggregate measures — rehearsal acceptance baselines, never runtime truth.
      MEASURES = %i[
        total_source_videos
        moderation_pending moderation_approved moderation_rejected
        owners_total owners_with_one_video owners_with_zero_video owners_with_multiple_videos
        owners_suspended
        missing_attachments duplicate_attachments missing_blobs
        unsupported_content_types checksum_size_inconsistencies malformed_moderation_values
        owner_not_imported
        blob_reuse_objects
        binding_conflicts
        max_duration_limit_seconds
        duration_present duration_missing duration_within_limit duration_over_limit duration_invalid
      ].freeze

      REASON_CODES = %w[
        owner_not_imported
        source_suspended_owner
        missing_attachment
        duplicate_attachment
        missing_blob
        unsupported_content_type
        checksum_size_inconsistent
        moderation_unmapped
        multiple_videos_per_owner
        blob_metadata_drift
        attachment_drift
        owner_binding_conflict
        preflight_error
      ].freeze

      def initialize
        @counts = Hash.new(0)
        @reasons = Hash.new(0)
        @measures = Hash.new(0)
      end

      def considered = bump(:videos_considered)

      def disposition!(name, reason: nil)
        raise ArgumentError, "unknown disposition #{name}" unless DISPOSITIONS.include?(name)

        bump(name)
        note!(reason) if reason
      end

      def created!(**counters)
        counters.each { |counter, n| add(counter, n) }
      end

      def note!(reason_code)
        raise ArgumentError, "unknown reason code #{reason_code.inspect}" unless REASON_CODES.include?(reason_code)

        @reasons[reason_code] += 1
      end

      def measure!(name, value = 1, mode: :increment)
        raise ArgumentError, "unknown measure #{name}" unless MEASURES.include?(name)

        case mode
        when :set then @measures[name] = value
        when :max then @measures[name] = [ @measures[name], value ].max
        when :increment then @measures[name] += value
        else raise ArgumentError, "unknown measure mode #{mode.inspect}"
        end
      end

      def count(counter) = @counts[counter]

      def reason_count(code) = @reasons[code]

      def measure(name) = @measures[name]

      def balanced?
        @counts[:videos_considered] == DISPOSITIONS.sum { |d| @counts[d] }
      end

      def to_h
        {
          "videos_considered" => @counts[:videos_considered],
          "balanced" => balanced?,
          "dispositions" => DISPOSITIONS.to_h { |d| [ d.to_s, @counts[d] ] },
          "created" => CREATION_COUNTERS.to_h { |c| [ c.to_s, @counts[c] ] },
          "measures" => MEASURES.to_h { |m| [ m.to_s, @measures[m] ] },
          "reason_codes" => REASON_CODES.to_h { |code| [ code, @reasons[code] ] }.select { |_, n| n.positive? }
        }
      end

      private

      def bump(counter) = @counts[counter] += 1

      def add(counter, n) = @counts[counter] += n
    end
  end
end
