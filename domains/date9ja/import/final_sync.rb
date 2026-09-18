require "digest"

module Date9ja
  module Import
    # Consumes protected normalized baseline/final bundles (SyncBundle). One
    # transaction, per-brand advisory lock, no external I/O or runtime awards.
    # A conflict rolls back the complete run. No source IDs/values in errors.
    class FinalSync
      class Conflict < StandardError; end

      def self.call(brand:, baseline:, desired:, apply: false)
        new(brand:, baseline:, desired:, apply:).call
      end

      def initialize(brand:, baseline:, desired:, apply:)
        @brand, @baseline, @desired, @apply = brand, baseline, desired, apply
        @counts = Hash.new(0)
      end

      def call
        raise Conflict, "wrong_brand" unless brand.slug == "date9ja"
        raise Conflict, "production_apply_forbidden" if Rails.env.production? && apply

        ActiveRecord::Base.transaction do
          bind = ActiveRecord::Relation::QueryAttribute.new("brand_id", brand.id, ActiveRecord::Type::Integer.new)
          ActiveRecord::Base.connection.exec_query("SELECT pg_advisory_xact_lock(9182026, $1::integer)", "Date9ja sync lock", [ bind ])
          Migration::ImportContext.as_migration do
            SyncBundle.validate!(baseline)
            SyncBundle.validate!(desired)
            @before = baseline.fetch("rows").index_by { |row| row.fetch("key") }
            @resolved = {}
            desired.fetch("rows").each { |row| sync_row(row) }
            SyncBundle.sync_children!(brand:, baseline:, desired:, resolved: @resolved, counts:)
            sync_removals!
            sync_lifecycle!
          end
          raise ActiveRecord::Rollback unless apply
        end
        counts.to_h
      end

      private

      attr_reader :brand, :baseline, :desired, :apply, :counts

      def sync_row(row)
        key = row.fetch("key")
        type = row.fetch("type")
        klass = type.constantize
        reference = Migration::ReferenceMap.resolve(source_system: "date9ja", source_entity: key[0], source_id: key[1])
        record = reference&.destination
        raise Conflict, "dangling_binding" if reference && !record
        raise Conflict, "binding_type_mismatch" if reference && reference.destination_type != type

        if %w[ProfilePhoto ProfileVideo].include?(type) && !record
          raise Conflict, "media_graph_required"
        end
        attrs = normalize(type, resolve_attrs(row.fetch("attributes")))
        attrs["created_at"] = row["created_at"] if !record && row["created_at"]
        if record
          assert_owned!(record)
          old = @before[key]
          raise Conflict, "missing_baseline" unless old || equivalent?(record, attrs)

          updates = old ? merge(record, normalize(type, resolve_attrs(old.fetch("attributes"))), attrs) : {}
          if updates.present?
            record.update!(updates)
            counts["updated"] += 1
          else
            counts["unchanged"] += 1
          end
        else
          raise Conflict, "baseline_binding_missing" if @before.key?(key)

          natural = SyncPolicy::NATURAL_KEYS[type]
          candidates = natural ? klass.where(attrs.slice(*natural)).limit(2).to_a : []
          raise Conflict, "ambiguous_native_event" if candidates.many?
          record = candidates.first
          if record
            raise Conflict, "native_event_conflict" unless equivalent?(record, attrs.except("created_at"))
            counts["native.adopted"] += 1
          else
            attrs["public_id"] = SecureRandom.uuid if klass.column_names.include?("public_id")
            record = klass.new(attrs)
            assert_owned!(record)
            record.save!
            counts["created"] += 1
          end
          Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: key[0], source_id: key[1],
            destination: record, brand: Migration::DestinationTypes.brand_owned?(type) ? brand : nil,
            importer_version: "date9ja-final-sync-v1", fingerprint: Digest::SHA256.hexdigest(row.to_json))
        end
        @resolved[key] = record
      end

      def resolve_attrs(attrs)
        attrs.transform_values do |value|
          if value.is_a?(Hash) && value.key?("$ref")
            key = value.fetch("$ref")
            target = @resolved[key] || Migration::ReferenceMap.resolved(source_system: "date9ja",
              source_entity: key[0], source_id: key[1])
            raise Conflict, "dependency_missing" unless target

            assert_owned!(target)
            target.id
          elsif value == { "$brand" => true }
            brand.id
          else
            value
          end
        end
      end

      def merge(record, old, final)
        final.each_with_object({}) do |(field, value), updates|
          current = record.attributes[field]
          next if equal_value?(record, field, old[field], value) || equal_value?(record, field, current, value)
          next if SyncPolicy::RETAIN_DESTINATION.include?(field) && current.present?
          if field.end_with?("_id") && !equal_value?(record, field, old[field], value)
            raise Conflict, "dependency_reassignment_forbidden"
          end

          if record.is_a?(User) && record.brand_memberships.where.not(brand:).exists?
            raise Conflict, "shared_identity_edit"
          end
          if field == "status" && restricted?(record, current) && !restricted?(record, value)
            next
          end
          if field == "visibility" && current == "hidden" && value == "visible" && current != old[field]
            next
          end
          raise Conflict, "concurrent_edit" unless equal_value?(record, field, current, old[field])

          raise Conflict, "append_only_ledger_change" if SyncPolicy::APPEND_ONLY.include?(record.class.name)

          updates[field] = value
        end
      end

      def normalize(type, attrs)
        if type == "Match"
          attrs["profile_a_id"], attrs["profile_b_id"] = attrs.values_at("profile_a_id", "profile_b_id").sort
        end
        attrs
      end

      def restricted?(record, value)
        (record.is_a?(BrandMembership) && %w[suspended deactivated left].include?(value)) ||
          (record.is_a?(Profile) && %w[suspended closed].include?(value)) ||
          (record.is_a?(Match) && value == "ended")
      end

      def equal_value?(record, field, left, right)
        type = record.class.type_for_attribute(field)
        type.cast(left) == type.cast(right)
      end

      def equivalent?(record, attrs)
        attrs.all? { |field, value| equal_value?(record, field, record.attributes[field], value) }
      end

      def assert_owned!(record)
        if record.respond_to?(:brand_id) && record.brand_id != brand.id
          raise Conflict, "cross_brand_target"
        end
        if record.is_a?(Credential) && record.identity_identifier.brand_id != brand.id
          raise Conflict, "cross_brand_credential"
        end
      end

      def sync_lifecycle!
        @resolved.values.grep(BrandMembership).each do |membership|
          next if membership.active? && membership.deleted_at.nil?

          Session.active.where(brand:, user: membership.user).find_each do |session|
            Identity::SessionRevoker.call(session:)
            counts["sessions.revoked"] += 1
          end
        end
        @resolved.values.grep(Profile).select { |profile| profile.deleted_at.present? }.each do |profile|
          active = Match.kept.where(brand:, status: :active).where("profile_a_id = :p OR profile_b_id = :p", p: profile.id)
          counts["matches.ended"] += active.update_all(status: Match.statuses.fetch("ended"))
        end
      end

      def sync_removals!
        desired_keys = desired.fetch("rows").map { |row| row.fetch("key") }
        (@before.keys - desired_keys).each do |key|
          row = @before.fetch(key)
          next if %w[User IdentityIdentifier Credential].include?(row.fetch("type"))

          record = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: key[0], source_id: key[1])
          raise Conflict, "removed_binding_missing" unless record

          assert_owned!(record)
          # Missing data is not a deletion instruction. The final bundle must
          # explicitly attest to each removal; absent/filtered rows abort.
          removal = desired.fetch("removals").find { |entry| entry.fetch("key") == key }
          raise Conflict, "unexplained_source_omission" unless removal
          next if record.respond_to?(:deleted_at) && record.deleted_at.present?

          if record.is_a?(Profile)
            membership = record.brand_membership
            raise Conflict, "source_deletion_requires_lifecycle" unless %w[source_deleted source_banned].include?(removal.fetch("reason"))

            record.update!(deleted_at: removal.fetch("at"), visibility: :hidden)
            membership.update!(status: removal.fetch("reason") == "source_banned" ? :suspended : :left)
            Match.kept.where(brand:).where("profile_a_id = :p OR profile_b_id = :p", p: record.id)
              .update_all(status: Match.statuses.fetch("ended"))
            Session.active.where(brand:, user: record.user).find_each { |session| Identity::SessionRevoker.call(session:) }
          elsif record.respond_to?(:deleted_at)
            record.update!(deleted_at: removal.fetch("at"))
          else
            raise Conflict, "unsupported_removal"
          end
          counts["removed"] += 1
        end
      end
    end
  end
end
