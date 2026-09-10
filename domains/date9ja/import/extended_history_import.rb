# frozen_string_literal: true

require "digest"

module Date9ja
  module Import
    # Imports every retained Date9ja operational / member-visible history table
    # that has no dedicated D8N runtime aggregate. Message reactions land in the
    # canonical MessageReaction model; everything else lands in the brand-scoped
    # Date9jaHistoryRecord ledger, typed by source entity, idempotent, and with
    # sensitive keys filtered out of the persisted payload.
    #
    # Like HistoricalGraphImport it never calls runtime services: historical
    # rows must not emit notifications, consume quota, or receive today's
    # timestamps. Each row runs in its own savepointed transaction.
    class ExtendedHistoryImport
      SOURCE_SYSTEM = "date9ja"
      IMPORTER_VERSION = "date9ja-extended-history-v1"
      INTERNAL_KEYS = %i[__owner_key __counterparty_key __occurred_at __status].freeze

      Result = Data.define(:reconciliation)

      def self.call(brand:, source:, importer_version: IMPORTER_VERSION)
        new(brand:, source:, importer_version:).call
      end

      def initialize(brand:, source:, importer_version:)
        @brand = brand
        @source = source
        @version = importer_version
        @reconciliation = ExtendedHistoryReconciliation.new
      end

      def call
        assert_brand!
        import_entitlements
        Snapshot::ExtendedHistorySource::ENTITIES.each_key do |entity|
          Array(@source.public_send(entity)).each { |row| import_row(entity, row) }
        end
        reconcile_trust_points!
        Result.new(@reconciliation)
      end

      private

      attr_reader :brand, :version, :reconciliation

      def assert_brand!
        raise ArgumentError, "extended history import requires Date9ja" unless brand&.slug == SOURCE_SYSTEM
      end

      def import_row(entity, raw)
        reconciliation.considered(entity)
        row = raw.to_h.transform_keys(&:to_sym)
        source_id = (row[:id] || row[:source_id]).to_s
        return reconciliation.skipped!(entity, "blank_source_id") if source_id.blank?

        accumulate_trust_points(entity, row)

        ActiveRecord::Base.transaction(requires_new: true) do
          if entity == :message_reactions
            import_reaction(entity, row, source_id)
          else
            import_ledger_row(entity, row, source_id)
          end
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        reconciliation.failed!(entity, "destination_conflict")
      rescue StandardError
        reconciliation.failed!(entity, "invalid_source_row")
      end

      def import_ledger_row(entity, row, source_id)
        if Date9jaHistoryRecord.exists?(brand:, source_entity: entity.to_s, source_id:)
          return reconciliation.already_imported!(entity)
        end

        owner_key = row[:__owner_key]
        user = owner_key ? resolve(:user, row[owner_key]) : nil
        return reconciliation.skipped!(entity, "owner_not_migrated") if owner_key && user.nil?

        profile = owner_key ? resolve(:profile, row[owner_key]) : nil
        occurred_at = row[row[:__occurred_at]] if row[:__occurred_at]
        status = row[row[:__status]] if row[:__status]

        payload = PayloadSanitizer.call(row.except(:id, :source_id, *INTERNAL_KEYS))
        payload.merge!(counterparty_binding(row))

        record = Date9jaHistoryRecord.create!(
          brand:, user:, profile:,
          source_entity: entity.to_s, source_id:,
          record_type: entity.to_s,
          status: status&.to_s.presence,
          occurred_at: occurred_at || row[:created_at] || row[:updated_at],
          payload:
        )
        bind!(record, entity, source_id, row)
        reconciliation.imported!(entity)
      end

      # Resolve the "other side" of a two-party historical row (profile view,
      # daily introduction, explore impression, tracked contact) to its D8N
      # public id so both ends are linked without persisting a raw source id.
      def counterparty_binding(row)
        key = row[:__counterparty_key]
        return {} if key.nil? || row[key].blank?

        target = resolve(:profile, row[key])
        {
          "counterparty_migrated" => target.present?,
          "counterparty_ref" => target&.public_id
        }.compact
      end

      def import_reaction(entity, row, source_id)
        return reconciliation.already_imported!(entity) if bound?(:message_reaction, source_id)

        message = resolve(:message, row[:message_id])
        return reconciliation.skipped!(entity, "message_not_migrated") if message.nil?

        reactor = resolve(:profile, row[:user_id])
        return reconciliation.skipped!(entity, "actor_not_migrated") if reactor.nil?

        emoji = (row[:emoji] || row[:reaction]).to_s.presence || "👍"
        created = row[:created_at] || message.created_at

        record = MessageReaction.find_or_initialize_by(
          brand:, message:, reactor_profile: reactor, emoji:
        )
        record.assign_attributes(created_at: created, updated_at: row[:updated_at] || created) if record.new_record?
        record.save!
        bind!(record, :message_reaction, source_id, row)
        reconciliation.imported!(entity)
      end

      def import_entitlements
        entity = :entitlements
        Array(@source.entitlements).each do |raw|
          reconciliation.considered(entity)
          row = raw.to_h.transform_keys(&:to_sym)
          user = resolve(:user, row[:id])
          next reconciliation.skipped!(entity, "owner_not_migrated") if user.nil?

          reconciliation.add_metric(:entitlement_trust_xp_total, row[:trust_xp].to_i)

          preserved = {
            "founding_member" => truthy(row[:founding_member]),
            "trust_xp" => row[:trust_xp]&.to_i,
            "subscription_status" => row[:subscription_status]&.to_s.presence,
            "premium_expires_at" => row[:premium_expires_at]&.then { |v| v.respond_to?(:iso8601) ? v.iso8601 : v.to_s }
          }.compact

          existing = user.metadata.fetch("date9ja", {})
          merged = existing.merge(preserved)
          next reconciliation.already_imported!(entity) if merged == existing

          user.update!(metadata: user.metadata.merge("date9ja" => merged))
          reconciliation.imported!(entity)
        rescue ActiveRecord::RecordInvalid
          reconciliation.failed!(entity, "destination_conflict")
        end
      end

      def truthy(value)
        [ true, "t", "true", "1", 1 ].include?(value)
      end

      # Independent trust-XP check (blocker ledger item 6): the sum of imported
      # trust-event points must equal the sum of the entitlement `trust_xp`
      # snapshot for the same migrated cohort. Recorded, not enforced — a
      # non-zero delta is a reconciliation finding for the operator.
      def accumulate_trust_points(entity, row)
        return unless entity == :trust_events

        # Scope the points sum to the migrated cohort so it is comparable to
        # entitlement_trust_xp_total, which only sums migrated users. Events
        # owned by a non-migrated (e.g. soft-deleted or seed) account are
        # excluded from both sides.
        owner_key = row[:__owner_key]
        return if owner_key && resolve(:user, row[owner_key]).nil?

        reconciliation.add_metric(:trust_event_points_total, row[:points].to_i)
      end

      def reconcile_trust_points!
        events = reconciliation.metric(:trust_event_points_total)
        entitlement = reconciliation.metric(:entitlement_trust_xp_total)
        reconciliation.add_metric(:trust_xp_delta, events - entitlement)
      end

      def resolve(kind, source_id)
        return nil if source_id.blank?

        record = Migration::ReferenceMap.resolved(
          source_system: SOURCE_SYSTEM, source_entity: kind.to_s, source_id: source_id.to_s
        )
        return nil unless record
        return nil if record.respond_to?(:brand_id) && record.brand_id && record.brand_id != brand.id

        record
      end

      def bound?(entity, source_id)
        Migration::ReferenceMap.resolve(
          source_system: SOURCE_SYSTEM, source_entity: entity.to_s, source_id: source_id.to_s
        ).present?
      end

      def bind!(record, entity, source_id, row)
        Migration::ReferenceMap.bind!(
          source_system: SOURCE_SYSTEM, source_entity: entity.to_s, source_id: source_id.to_s,
          destination: record, brand:, importer_version: version,
          fingerprint: Digest::SHA256.hexdigest(row.to_h.sort_by { |k, _| k.to_s }.to_s)[0, 32]
        )
      end
    end
  end
end
