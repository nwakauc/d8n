# frozen_string_literal: true

module Date9ja
  module Import
    # First structural movement of Date9ja members into D8N.
    #
    #   Date9ja::Snapshot::UserSource
    #     -> D8N User + IdentityIdentifier(email[/phone])
    #     -> Credential(password) + CredentialPasswordHash (legacy digest VERBATIM)
    #     -> Date9ja BrandMembership
    #     -> shared Profile (non-sensitive fields only)
    #     -> Migration::ReferenceMap bindings (the migration identity spine)
    #     -> deterministic, PII-free Reconciliation
    #
    # Every source row is processed in its own savepointed transaction: a row
    # that fails leaves nothing behind and is retried cleanly on the next run.
    # Idempotent: a row whose `user` reference already resolves is counted as
    # already-imported only when every required downstream binding and record is
    # present and consistent; a lone User binding is an incomplete prior run.
    class IdentityImport
      SOURCE_SYSTEM = "date9ja"

      # 60-char bcrypt as produced by Devise ($2a/$2b/$2y).
      BCRYPT_RE = %r{\A\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}\z}

      Result = Data.define(:reconciliation)

      class WrongBrand < StandardError; end

      def self.call(...) = new(...).call

      def initialize(brand:, source:, importer_version: FieldMapping::IMPORTER_VERSION)
        @brand = brand
        @source = source
        @importer_version = importer_version
        @reconciliation = Reconciliation.new
      end

      def call
        assert_brand!

        @source.each do |record|
          @reconciliation.considered
          import_one(record)
        end

        Result.new(@reconciliation)
      end

      private

      attr_reader :brand, :reconciliation

      def assert_brand!
        return if brand&.slug == SOURCE_SYSTEM && brand.active? && brand.deleted_at.nil?

        raise WrongBrand, "identity import requires the active date9ja brand"
      end

      def import_one(record)
        return reconciliation.skipped!("source_soft_deleted") if record.soft_deleted?
        return reconciliation.skipped!("source_banned") if record.banned?

        existing = reference("user", record)
        if existing
          return already_imported_or_dangling(existing, record)
        end

        email = Identity::LoginIdentifier.call(record.email)
        unless email
          reconciliation.anomaly!(:missing_identifiers)
          return reconciliation.failed!("email_unparseable")
        end

        if colliding_identifier?(:email, email.lookup_values)
          reconciliation.anomaly!(:normalization_collisions)
          return reconciliation.failed!("email_collision")
        end

        digest = record.encrypted_password.to_s
        return reconciliation.skipped!("credential_hash_unusable") if digest.empty?

        unless BCRYPT_RE.match?(digest)
          reconciliation.anomaly!(:malformed_rows)
          return reconciliation.failed!("credential_hash_unusable")
        end

        phone = resolve_phone(record)

        persist(record, email:, phone:, digest:)
      end

      def already_imported_or_dangling(reference, record)
        if !reference.resolvable?
          reconciliation.anomaly!(:binding_conflicts)
          reconciliation.failed!("dangling_binding")
        elsif complete_import?(reference.destination, record)
          reconciliation.already_imported!
        else
          reconciliation.anomaly!(:binding_conflicts)
          reconciliation.failed!("incomplete_binding")
        end
      end

      def complete_import?(user, record)
        refs = %w[identity_email password_credential membership profile].map do |entity|
          reference(entity, record)
        end
        return false unless refs.all? { |ref| ref&.resolvable? }

        email_identifier, credential, membership, profile = refs.map(&:destination)
        email_identifier.user_id == user.id && email_identifier.email? && email_identifier.deleted_at.nil? &&
          credential.user_id == user.id && credential.password? && credential.active? && credential.deleted_at.nil? &&
          credential.identity_identifier_id == email_identifier.id &&
          credential.credential_password_hash&.password_hash == record.encrypted_password &&
          membership.user_id == user.id && membership.brand_id == brand.id &&
          membership.status == FieldMapping.membership_status(record).to_s && membership.deleted_at.nil? &&
          profile.user_id == user.id && profile.brand_id == brand.id && profile.deleted_at.nil? &&
          profile.status == FieldMapping.profile_status(record).to_s &&
          profile.visibility == FieldMapping.profile_visibility(record).to_s &&
          profile.brand_membership_id == membership.id
      end

      # Returns the phone LoginIdentifier to import, or nil (absent / unparseable
      # / colliding). Non-fatal for the row — a reason code is recorded.
      def resolve_phone(record)
        return nil if record.phone.to_s.strip.empty?

        phone = Identity::LoginIdentifier.call(record.phone, brand: brand)
        unless phone
          reconciliation.note!("phone_unparseable")
          return nil
        end

        if colliding_identifier?(:phone, phone.lookup_values)
          reconciliation.anomaly!(:normalization_collisions)
          reconciliation.note!("phone_collision")
          return nil
        end

        phone
      end

      def persist(record, email:, phone:, digest:)
        ActiveRecord::Base.transaction(requires_new: true) do
          user = User.create!
          bind!(user, "user", record)

          email_identifier = user.identity_identifiers.create!(
            kind: :email,
            normalized_value: email.normalized_value,
            verified_at: FieldMapping.email_verified_at(record)
          )
          bind!(email_identifier, "identity_email", record)
          identifiers = 1

          if phone
            phone_identifier = user.identity_identifiers.create!(
              kind: :phone,
              normalized_value: phone.normalized_value,
              verified_at: FieldMapping.phone_verified_at(record)
            )
            bind!(phone_identifier, "identity_phone", record)
            identifiers += 1
          end

          credential = user.credentials.create!(
            identity_identifier: email_identifier,
            kind: :password,
            status: :active,
            verified_at: FieldMapping.email_verified_at(record)
          )
          # Legacy Devise digest copied byte-for-byte. NEVER PasswordEngine.set!
          # (that would rehash). Compatibility is VERIFIED (SNAPSHOT-RUNBOOK §10).
          CredentialPasswordHash.create!(
            credential: credential,
            credential_kind: Credential.kinds.fetch("password"),
            password_hash: digest,
            password_changed_at: FieldMapping.password_changed_at(record)
          )
          bind!(credential, "password_credential", record)

          membership = BrandMembership.create!(
            user: user, brand: brand, status: FieldMapping.membership_status(record)
          )
          bind!(membership, "membership", record, brand: brand)

          profile = Profile.create!(
            user: user, brand: brand, brand_membership: membership,
            **FieldMapping.profile_attributes(record)
          )
          bind!(profile, "profile", record, brand: brand)

          reconciliation.imported!(
            users_created: 1,
            identifiers_created: identifiers,
            credentials_created: 1,
            password_hashes_created: 1,
            memberships_created: 1,
            profiles_created: 1,
            # user + email identifier + credential + membership + profile, plus
            # the phone identifier when present.
            legacy_references_created: 4 + identifiers
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        reconciliation.anomaly!(:malformed_rows)
        reconciliation.failed!(e.record.is_a?(Profile) ? "profile_invalid" : "source_row_error")
      rescue Migration::ReferenceMap::ImmutableBinding, Migration::ReferenceMap::DestinationConflict
        reconciliation.anomaly!(:binding_conflicts)
        reconciliation.failed!("binding_conflict")
      rescue StandardError
        reconciliation.failed!("source_row_error")
      end

      def bind!(destination, entity, record, brand: nil)
        Migration::ReferenceMap.bind!(
          source_system: SOURCE_SYSTEM,
          source_entity: entity,
          source_id: record.source_id,
          destination: destination,
          importer_version: @importer_version,
          brand: brand,
          fingerprint: record.fingerprint
        )
      end

      def reference(entity, record)
        Migration::ReferenceMap.resolve(
          source_system: SOURCE_SYSTEM, source_entity: entity, source_id: record.source_id
        )
      end

      # An existing kept identifier for one of `values` that this run has not
      # just created for the same source row — i.e. a genuine normalization
      # collision that must never be silently merged.
      def colliding_identifier?(kind, values)
        IdentityIdentifier.kept.exists?(kind: kind, normalized_value: values)
      end
    end
  end
end
