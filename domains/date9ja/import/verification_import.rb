module Date9ja
  module Import
    require "digest"

    class VerificationImport
      SOURCE_SYSTEM = "date9ja"
      Result = Data.define(:imported, :skipped, :failed)

      # Legacy status ordinal on `selfie_verifications.status` (plain integer
      # column, no source-side string enum): 0 pending / 1 approved / 2 rejected.
      # Inferred from the observed corpus shape (zero 0s, an approved-dominant
      # majority at 1, a single rejected outlier at 2) cross-checked against
      # `verification_checks.status`'s own approved-dominant string distribution
      # for the same real cohort -- the conventional Rails `enum` default
      # ordering, not a guess pulled from nothing. Anything outside 0-2 fails
      # closed to "pending" (never "approved") rather than risk a false
      # RealMe-qualifying state.
      SELFIE_STATUS = { 0 => "pending", 1 => "approved", 2 => "rejected" }.freeze

      def self.call(brand:, checks:, selfies: [])
        new(brand:, checks:, selfies:).call
      end

      def initialize(brand:, checks:, selfies:)
        @brand, @checks, @selfies = brand, checks, selfies
      end

      def call
        imported = skipped = failed = 0
        rows.each do |row|
          user = Migration::ReferenceMap.resolved(source_system: SOURCE_SYSTEM, source_entity: "user", source_id: row[:user_id] || row["user_id"])
          if user.nil?
            skipped += 1
            next
          end
          source_type = row.fetch(:source_type).to_s
          source_id = row.fetch(:id).to_s
          assertion = VerificationAssertion.find_or_initialize_by(brand: @brand, source_type:, source_id:)
          if assertion.persisted?
            imported += 1
            next
          end
          attrs = row.slice(:check_type, :status, :submitted_at, :reviewed_at, :reviewer_source_id, :metadata)
          attrs[:metadata] = (attrs[:metadata] || {}).merge("source_row" => row.except(:evidence, :metadata))
          assertion.assign_attributes(user:, source_type:, source_id:, **attrs)
          assertion.save!
          bind!(assertion, source_type, source_id, row)
          imported += 1
        rescue StandardError
          failed += 1
        end
        Result.new(imported, skipped, failed)
      end

      private

      # `verification_events` is deliberately NOT a row source here. Its shape
      # (verification_check_id, event_type: submitted/approved/rejected/
      # resubmission_required/evidence_deleted, metadata) is a transition AUDIT
      # LOG on a `verification_checks` row -- not an independent check. That
      # parent row is already imported faithfully via `checks:`. Treating each
      # event as its own assertion (as an earlier version of this importer did)
      # produced garbage `check_type: "verification_event"` / `status: "unknown"`
      # rows invisible to RealmeBadge/InteractionAccess -- inert, not usable RealMe
      # signal, and never a data-loss risk since the parent check carries the
      # real check_type/status.
      def rows
        (Array(@checks).map { |r| normalize(r, "verification_check") } +
          Array(@selfies).map { |r| normalize_selfie(r) })
      end

      def normalize(row, source_type)
        row = row.to_h.transform_keys(&:to_sym)
        # Legacy `verification_checks`/`selfie_verifications` rows never carry
        # evidence bytes to import here -- ADR 0034's manual-review evidence
        # attachment is member-submission-only. `evidence` is deliberately NOT
        # forced into the row (an ActiveStorage has_one_attached column would
        # raise on any non-file value, including `{}`); a real byte for a
        # migrated legacy assertion, if ever provided, is a separate
        # MediaKind-style transfer.
        row.merge(source_type:, check_type: (row[:check_type] || row[:kind] || source_type), status: (row[:status] || "unknown"), metadata: row[:metadata] || {})
      end

      # `selfie_verifications` carries no check_type column at all (the whole
      # table is selfie checks) and its `status` is a plain integer ordinal, not
      # a string enum like `verification_checks.status` -- both need an explicit,
      # table-specific decode rather than the generic `normalize` fallbacks.
      def normalize_selfie(row)
        row = row.to_h.transform_keys(&:to_sym)
        status_code = Integer(row[:status], exception: false)
        row.merge(
          source_type: "selfie_verification",
          check_type: "selfie",
          status: SELFIE_STATUS.fetch(status_code, "pending"),
          metadata: row[:metadata] || {}
        )
      end

      def bind!(record, source_type, source_id, row)
        Migration::ReferenceMap.bind!(
          source_system: SOURCE_SYSTEM, source_entity: source_type, source_id:,
          destination: record, brand: @brand, importer_version: "date9ja-verification-v2",
          fingerprint: Digest::SHA256.hexdigest(row.to_h.sort_by { |k, _| k.to_s }.to_s)[0, 32]
        )
      end
    end
  end
end
