# frozen_string_literal: true

module Date9ja
  module Import
    require "digest"
    # Preserves Date9ja lifecycle / moderation context that the identity and
    # readiness passes do not carry:
    #
    #   * every soft-deleted source member becomes an `identity_tombstone`
    #     Date9jaHistoryRecord (no D8N User is resurrected) capturing the
    #     deletion reason / code / comment / timestamp, so a retained graph edge
    #     that points at a deleted account has an explainable other end;
    #   * every retained member carrying a suspension / ban / discovery
    #     restriction gets a `moderation_state` record capturing reason, note,
    #     actor, and timestamps.
    #
    # Idempotent (unique on brand + source_entity + source_id) and PII-free:
    # free-text reasons/notes are kept as operator context in the ledger payload,
    # never surfaced through a public serializer.
    class LifecycleImport
      SOURCE_SYSTEM = "date9ja"
      Result = Data.define(:reconciliation)

      DELETION_KEYS = %i[deletion_reason deletion_reason_code deletion_comment deleted_at].freeze
      MODERATION_KEYS = %i[
        suspended_at suspension_reason banned_at ban_reason flagged_for_moderation_at
        discovery_restricted_at discovery_restricted_by_id discovery_restriction_reason
        discovery_restriction_note
      ].freeze

      def self.call(brand:, source:)
        new(brand:, source:).call
      end

      def initialize(brand:, source:)
        @brand = brand
        @source = source
        @reconciliation = ExtendedHistoryReconciliation.new
      end

      def call
        raise ArgumentError, "lifecycle import requires Date9ja" unless @brand&.slug == SOURCE_SYSTEM

        Array(@source.users).each do |raw|
          row = raw.to_h.transform_keys(&:to_sym)
          import_tombstone(row) if row[:deleted_at].present?
          import_moderation_state(row) if moderation?(row)
        end
        Result.new(@reconciliation)
      end

      private

      def import_tombstone(row)
        upsert(:identity_tombstone, row, DELETION_KEYS, status: "deleted", occurred_at: row[:deleted_at])
      end

      def import_moderation_state(row)
        status = if row[:banned_at].present? then "banned"
        elsif row[:suspended_at].present? then "suspended"
        else "discovery_restricted"
        end
        occurred_at = row[:banned_at] || row[:suspended_at] || row[:discovery_restricted_at]
        actor = resolve_user(row[:discovery_restricted_by_id])
        upsert(:moderation_state, row, MODERATION_KEYS, status:, occurred_at:,
          extra: {
            "restricting_actor_present" => actor.present?,
            "restricting_actor_ref" => actor&.public_id
          }.compact)
      end

      def upsert(entity, row, keys, status:, occurred_at:, extra: {})
        @reconciliation.considered(entity)
        source_id = row[:id].to_s
        return @reconciliation.skipped!(entity, "blank_source_id") if source_id.blank?
        if Date9jaHistoryRecord.exists?(brand: @brand, source_entity: entity.to_s, source_id:)
          return @reconciliation.already_imported!(entity)
        end

        user = resolve_user(row[:id])
        payload = PayloadSanitizer.call(row.slice(*keys).compact.merge(extra))
        Date9jaHistoryRecord.create!(
          brand: @brand, user:, source_entity: entity.to_s, source_id:,
          record_type: entity.to_s, status:, occurred_at:, payload:
        )
        record = Date9jaHistoryRecord.find_by!(brand: @brand, source_entity: entity.to_s, source_id:)
        Migration::ReferenceMap.bind!(
          source_system: SOURCE_SYSTEM, source_entity: entity.to_s, source_id:,
          destination: record, brand: @brand, importer_version: "date9ja-lifecycle-v2",
          fingerprint: Digest::SHA256.hexdigest(row.to_h.sort_by { |k, _| k.to_s }.to_s)[0, 32]
        )
        @reconciliation.imported!(entity)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        @reconciliation.failed!(entity, "destination_conflict")
      end

      def moderation?(row)
        row[:suspended_at].present? || row[:banned_at].present? || row[:discovery_restricted_at].present?
      end

      def resolve_user(source_id)
        return nil if source_id.blank?

        Migration::ReferenceMap.resolved(source_system: SOURCE_SYSTEM, source_entity: "user", source_id: source_id.to_s)
      end
    end
  end
end
