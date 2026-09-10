module Date9ja
  module Import
    require "digest"

    class VerificationImport
      SOURCE_SYSTEM = "date9ja"
      Result = Data.define(:imported, :skipped, :failed)

      def self.call(brand:, checks:, events: [], selfies: [])
        new(brand:, checks:, events:, selfies:).call
      end

      def initialize(brand:, checks:, events:, selfies:)
        @brand, @checks, @events, @selfies = brand, checks, events, selfies
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
          attrs = row.slice(:check_type, :status, :submitted_at, :reviewed_at, :reviewer_source_id, :evidence, :metadata)
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

      def rows
        (Array(@checks).map { |r| normalize(r, "verification_check") } +
          Array(@events).map { |r| normalize(r, "verification_event") } +
          Array(@selfies).map { |r| normalize(r, "selfie_verification") })
      end

      def normalize(row, source_type)
        row = row.to_h.transform_keys(&:to_sym)
        row.merge(source_type:, check_type: (row[:check_type] || row[:kind] || source_type), status: (row[:status] || "unknown"), evidence: row[:evidence] || {}, metadata: row[:metadata] || {})
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
