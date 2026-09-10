module Date9ja
  module Import
    # Catch-all owner for Date9ja member-visible and operational history which
    # has no one-to-one D8N runtime aggregate yet. It is intentionally typed by
    # source entity/record_type, idempotent, brand-scoped, and never copies raw
    # credentials or authentication secrets into payload.
    class HistoryRecordImport
      SOURCE_SYSTEM = "date9ja"
      Result = Data.define(:considered, :imported, :already_imported, :skipped, :failed)

      def self.call(brand:, rows:)
        new(brand:, rows:).call
      end

      def initialize(brand:, rows:)
        @brand = brand
        @rows = rows
      end

      def call
        counters = Hash.new(0)
        Array(@rows).each do |input|
          counters[:considered] += 1
          row = input.to_h.transform_keys(&:to_sym)
          entity = row[:source_entity].to_s.presence || row[:entity].to_s
          source_id = (row[:source_id] || row[:id]).to_s
          if entity.blank? || source_id.blank?
            counters[:skipped] += 1
            next
          end
          existing = Date9jaHistoryRecord.find_by(brand: @brand, source_entity: entity, source_id: source_id)
          if existing
            counters[:already_imported] += 1
            next
          end

          user = resolve_user(row[:user_id])
          profile = resolve_profile(row[:profile_id] || row[:user_id])
          Date9jaHistoryRecord.create!(
            brand: @brand, user:, profile:, source_entity: entity, source_id:,
            record_type: (row[:record_type] || entity).to_s,
            status: row[:status]&.to_s,
            occurred_at: row[:occurred_at] || row[:created_at] || row[:updated_at],
            payload: sanitize(row.except(:user, :profile, :user_id, :profile_id, :id, :source_id, :source_entity))
          )
          counters[:imported] += 1
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          counters[:failed] += 1
        end
        Result.new(*%i[considered imported already_imported skipped failed].map { |key| counters[key] })
      end

      private

      def resolve_user(source_id)
        return nil if source_id.blank?

        ref = Migration::ReferenceMap.resolved(source_system: SOURCE_SYSTEM, source_entity: "user", source_id:)
        ref&.destination if ref&.respond_to?(:destination_type) && ref.destination_type == "User"
      end

      def resolve_profile(source_id)
        return nil if source_id.blank?

        ref = Migration::ReferenceMap.resolved(source_system: SOURCE_SYSTEM, source_entity: "profile", source_id:)
        ref&.destination if ref&.respond_to?(:destination_type) && ref.destination_type == "Profile"
      end

      def sanitize(value)
        PayloadSanitizer.call(value)
      end
    end
  end
end
