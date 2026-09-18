module Date9ja
  module Import
    # Explicit data-repair boundary, not a relaxation of ReferenceMap immutability.
    # Only membership references may change, using a validated profile anchor.
    # Caller stores the protected preview plan before requesting application.
    class MembershipReferenceRepair
      def self.plan(brand:, source:)
        raise ReferenceRepair::Conflict, "wrong_brand" unless brand.slug == "date9ja"

        source.filter_map do |row|
          next if row.soft_deleted? || row.banned?
          profile = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile", source_id: row.source_id)
          raise ReferenceRepair::Conflict, "missing_presence_binding" unless profile.is_a?(Profile) && profile.brand_id == brand.id
          membership = profile.brand_membership
          raise ReferenceRepair::Conflict, "presence_ownership_mismatch" unless membership.brand_id == brand.id && membership.user_id == profile.user_id
          identifier = Identity::LoginIdentifier.call(row.email, brand:)
          raise ReferenceRepair::Conflict, "baseline_identifier_invalid" unless identifier&.kind == :email
          matches = IdentityIdentifier.kept.where(user: profile.user, brand:, kind: :email, normalized_value: identifier.lookup_values)
          raise ReferenceRepair::Conflict, "baseline_identifier_ambiguous" unless matches.count == 1
          existing = Migration::ReferenceMap.resolve(source_system: "date9ja", source_entity: "membership", source_id: row.source_id)
          next if existing && existing.destination_type == "BrandMembership" && existing.destination_id == membership.id && existing.brand_id == brand.id
          raise ReferenceRepair::Conflict, "unexpected_membership_binding" if existing &&
            (existing.destination_type != "BrandMembership" || existing.brand_id != brand.id)

          { "source_id" => row.source_id, "expected" => existing&.attributes,
            "profile_id" => profile.id, "membership_id" => membership.id }
        end
      end

      def self.apply!(brand:, source:, expected_plan:)
        raise ReferenceRepair::Conflict, "production_apply_forbidden" if Rails.env.production?
        ActiveRecord::Base.transaction do
          # Lock references so the stored plan cannot silently become stale.
          LegacyReference.for_source("date9ja").where(source_entity: %w[profile membership]).lock.load
          actual = plan(brand:, source:).as_json
          raise ReferenceRepair::Conflict, "stale_repair_plan" unless actual == expected_plan.as_json
          # Delete only the attested erroneous mapping rows. Domain records are
          # untouched. Reclaim via ReferenceMap so both ownership and uniqueness
          # constraints still apply. Any conflict rolls back all corrections.
          ids = actual.filter_map { |entry| entry["expected"]&.fetch("id") }
          LegacyReference.where(id: ids).delete_all
          actual.each do |entry|
            target = BrandMembership.find(entry.fetch("membership_id"))
            Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: "membership",
              source_id: entry.fetch("source_id"), destination: target, brand:,
              importer_version: "date9ja-membership-reference-repair-v1")
          end
          { "membership_bindings.corrected" => actual.size }
        end
      end
    end
  end
end
