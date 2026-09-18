module Date9ja
  module Import
    # Restores an omitted brand-scoped phone; never links accounts across brands.
    # Source ownership is established by the bound profile and baseline email.
    class PhoneIdentityRepair
      def self.plan(brand:, source:)
        raise ReferenceRepair::Conflict, "wrong_brand" unless brand.slug == "date9ja"
        source.filter_map do |row|
          next if row.soft_deleted? || row.banned? || row.phone.blank?
          phone = Identity::LoginIdentifier.call(row.phone, brand:)
          next unless phone&.kind == :phone
          profile = Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile", source_id: row.source_id)
          raise ReferenceRepair::Conflict, "missing_presence_binding" unless profile.is_a?(Profile) && profile.brand_id == brand.id
          email = Identity::LoginIdentifier.call(row.email, brand:)
          valid_email = email&.kind == :email && IdentityIdentifier.kept.where(brand:, user: profile.user,
            kind: :email, normalized_value: email.lookup_values).count == 1
          raise ReferenceRepair::Conflict, "baseline_identifier_ambiguous" unless valid_email
          phones = IdentityIdentifier.kept.where(brand:, kind: :phone, normalized_value: phone.lookup_values)
          next if phones.exists? # bindings for existing identities use ReferenceRepair
          raise ReferenceRepair::Conflict, "native_phone_edit" if IdentityIdentifier.where(brand:, user: profile.user, kind: :phone).exists?
          existing = Migration::ReferenceMap.resolve(source_system: "date9ja", source_entity: "identity_phone", source_id: row.source_id)
          raise ReferenceRepair::Conflict, "unexpected_phone_binding" if existing

          { "source_id" => row.source_id, "user_id" => profile.user_id,
            "normalized_value" => phone.normalized_value, "verified_at" => IdentityIdentifier.type_for_attribute("verified_at").cast(FieldMapping.phone_verified_at(row))&.iso8601(6) }
        end
      end

      def self.apply!(brand:, source:, expected_plan:)
        raise ReferenceRepair::Conflict, "production_apply_forbidden" if Rails.env.production?
        ActiveRecord::Base.transaction do
          brand.lock!
          actual = plan(brand:, source:).as_json
          raise ReferenceRepair::Conflict, "stale_repair_plan" unless actual == expected_plan.as_json
          actual.each do |entry|
            identifier = IdentityIdentifier.create!(brand:, user_id: entry.fetch("user_id"), kind: :phone,
              normalized_value: entry.fetch("normalized_value"), verified_at: entry.fetch("verified_at"))
            Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: "identity_phone",
              source_id: entry.fetch("source_id"), destination: identifier, importer_version: "date9ja-phone-identity-repair-v1")
          end
          { "phone_identities.created" => actual.size }
        end
      end
    end
  end
end
