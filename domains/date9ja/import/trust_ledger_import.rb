module Date9ja
  module Import
    # Re-projects the trust_events/trust_adjustments rows already imported by
    # ExtendedHistoryImport (as generic Date9jaHistoryRecord rows) into the
    # proper ADR 0025 TrustEvent/TrustAdjustment shape. Deliberately reads only
    # already-migrated, already-reconciled D8N data — no legacy snapshot/DB
    # access, no re-resolution of the owning user (Date9jaHistoryRecord already
    # carries it). Idempotent the same way every other importer slice is:
    # bound via Migration::ReferenceMap keyed by the legacy row's own id.
    class TrustLedgerImport
      SOURCE_SYSTEM = "date9ja"
      IMPORTER_VERSION = "date9ja-trust-ledger-v1"

      Result = Data.define(:imported, :skipped, :failed)

      def self.call(brand:)
        new(brand:).call
      end

      def initialize(brand:)
        @brand = brand
      end

      def call
        imported = skipped = failed = 0
        source_records.find_each do |record|
          result = import_record(record)
          case result
          when :imported then imported += 1
          when :skipped then skipped += 1
          end
        rescue StandardError
          failed += 1
        end
        Result.new(imported, skipped, failed)
      end

      private

      attr_reader :brand

      def source_records
        Date9jaHistoryRecord.where(brand:, source_entity: %w[trust_events trust_adjustments])
      end

      def import_record(record)
        klass = record.source_entity == "trust_events" ? TrustEvent : TrustAdjustment
        idempotency_key = "#{SOURCE_SYSTEM}:#{record.source_entity}:#{record.source_id}"
        return :skipped if klass.exists?(brand:, idempotency_key:)

        row = record_attrs(klass, record)
        entry = klass.create!(row)
        bind!(entry, record)
        :imported
      end

      def record_attrs(klass, record)
        idempotency_key = "#{SOURCE_SYSTEM}:#{record.source_entity}:#{record.source_id}"
        common = {
          brand:, user: record.user, idempotency_key:,
          occurred_at: record.occurred_at || record.created_at,
          metadata: { "legacy_history_record_id" => record.id }
        }

        if klass == TrustEvent
          common.merge(
            profile: record.profile,
            event_type: record.payload["event_type"],
            points: record.payload["points"].to_i,
            source_type: record.payload["source_type"]
          )
        else
          common.merge(
            points: record.payload["points"].to_i,
            reason_code: record.payload["reason_code"],
            appeal_status: record.status.presence || "not_requested",
            resolved_at: record.payload["resolved_at"].presence && Time.iso8601(record.payload["resolved_at"]),
            metadata: common[:metadata].merge(
              "legacy_actor_id" => record.payload["actor_id"]
            ).compact
          )
        end
      end

      def bind!(entry, record)
        Migration::ReferenceMap.bind!(
          source_system: SOURCE_SYSTEM, source_entity: entry.is_a?(TrustEvent) ? "trust_event" : "trust_adjustment",
          source_id: record.source_id, destination: entry, brand:, importer_version: IMPORTER_VERSION
        )
      end
    end
  end
end
