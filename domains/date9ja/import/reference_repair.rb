module Date9ja
  module Import
    # Recover only from the already-bound dating presence and an approved
    # baseline source. Never identify/merge an account by email alone.
    class ReferenceRepair
      class Conflict < StandardError; end

      def self.call(brand:, source:, apply: false)
        new(brand:, source:, apply:).call
      end

      def initialize(brand:, source:, apply:)
        @brand, @source, @apply = brand, source, apply
      end

      def call
        raise Conflict, "wrong_brand" unless brand.slug == "date9ja"
        raise Conflict, "production_apply_forbidden" if apply && Rails.env.production?

        counts = Hash.new(0)
        ActiveRecord::Base.transaction do
          source.each do |row|
            next if row.soft_deleted? || row.banned?

            profile = resolve!("profile", row)
            membership = resolve!("membership", row)
            user = profile.user
            unless profile.brand_id == brand.id && membership.brand_id == brand.id &&
                membership.user_id == user.id && profile.brand_membership_id == membership.id
              raise Conflict, "presence_ownership_mismatch"
            end

            email = identifier!(user, row.email, :email)
            credentials = Credential.kept.where(user:, identity_identifier: email, kind: :password).limit(2).to_a
            raise Conflict, "credential_ambiguous" unless credentials.one?
            hash = credentials.sole.credential_password_hash&.password_hash
            if (hash && !IdentityImport::BCRYPT_RE.match?(hash)) ||
                (hash.nil? && IdentityImport::BCRYPT_RE.match?(row.encrypted_password.to_s))
              raise Conflict, "credential_hash_incomplete"
            end

            targets = { "user" => user, "identity_email" => email, "password_credential" => credentials.sole }
            if row.phone.present?
              normalized = Identity::LoginIdentifier.call(row.phone, brand:)
              if normalized && normalized.kind == :phone
                phones = IdentityIdentifier.kept.where(user:, brand:, kind: :phone,
                  normalized_value: normalized.lookup_values).limit(2).to_a
                raise Conflict, "phone_ambiguous" if phones.many?
                targets["identity_phone"] = phones.sole if phones.one?
                if phones.empty?
                  colliding = IdentityIdentifier.kept.where(brand:, kind: :phone, normalized_value: normalized.lookup_values).exists?
                  counts[colliding ? "phone_collision_excluded" : "phone_not_imported"] += 1
                end
              else
                counts["phone_unparseable"] += 1
              end
            end
            targets.each do |entity, destination|
              existing = reference(entity, row)
              if existing && (existing.destination_type != destination.class.name ||
                  existing.destination_id != destination.id || existing.brand_id.present?)
                raise Conflict, "immutable_binding_conflict"
              end
              counts["#{entity}.reconciled"] += 1
              next if existing

              counts["#{entity}.missing"] += 1
              Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: entity,
                source_id: row.source_id, destination:, importer_version: "date9ja-reference-repair-v1",
                fingerprint: row.fingerprint) if apply
            end
          end
        end
        counts.to_h
      end

      private

      attr_reader :brand, :source, :apply

      def reference(entity, row)
        Migration::ReferenceMap.resolve(source_system: "date9ja", source_entity: entity, source_id: row.source_id)
      end

      def resolve!(entity, row)
        reference(entity, row)&.destination || raise(Conflict, "missing_presence_binding")
      end

      def identifier!(user, value, kind)
        normalized = Identity::LoginIdentifier.call(value, brand:)
        raise Conflict, "baseline_identifier_invalid" unless normalized && normalized.kind.to_sym == kind

        identifiers = IdentityIdentifier.kept.where(user:, brand:, kind:,
          normalized_value: normalized.lookup_values).limit(2).to_a
        raise Conflict, "baseline_identifier_ambiguous" unless identifiers.one?

        identifiers.sole
      end
    end
  end
end
