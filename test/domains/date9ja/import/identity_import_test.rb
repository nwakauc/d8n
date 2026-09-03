# frozen_string_literal: true

require "test_helper"
require "bcrypt"

module Date9ja
  module Import
    class IdentityImportTest < ActiveSupport::TestCase
      SYNTHETIC_PASSWORD = "correct-horse-battery"

      setup do
        @brand = Brand.create!(
          slug: "date9ja", name: "Date9ja", status: :active,
          auth_methods: %w[email_password phone_password]
        )
      end

      # --- helpers --------------------------------------------------------------

      def synthetic_digest(password = SYNTHETIC_PASSWORD)
        BCrypt::Password.create(password, cost: BCrypt::Engine::MIN_COST).to_s
      end

      def row(id:, **overrides)
        {
          "id" => id,
          "public_id" => "pub-#{id}",
          "email" => "member#{id}@date9ja.example",
          "phone" => nil,
          "encrypted_password" => synthetic_digest,
          "confirmed_at" => Time.utc(2024, 1, 1),
          "phone_verified_at" => nil,
          "created_at" => Time.utc(2023, 1, 1),
          "deleted_at" => nil,
          "suspended_at" => nil,
          "banned_at" => nil,
          "profile_hidden" => false,
          "onboarding_completed_at" => Time.utc(2024, 2, 1),
          "date_of_birth" => Date.new(1994, 6, 15),
          "gender" => "woman",
          "display_name" => "Member #{id}",
          "city" => "Lagos",
          "country_of_residence" => "NG",
          "about_me" => "hello there",
          "ideal_partner_description" => "someone kind",
          "languages_spoken" => nil
        }.merge(overrides.transform_keys(&:to_s))
      end

      def import(rows)
        source = Snapshot::UserSource.new(rows: rows)
        IdentityImport.call(brand: @brand, source: source)
      end

      def resolved(entity, source_id)
        Migration::ReferenceMap.resolved(
          source_system: "date9ja", source_entity: entity, source_id: source_id.to_s
        )
      end

      # --- clean import ------------------------------------------------------

      test "imports a clean source user into the full D8N identity + profile shape" do
        result = nil
        assert_difference(
          -> { User.count } => 1, -> { Credential.count } => 1,
          -> { CredentialPasswordHash.count } => 1, -> { BrandMembership.count } => 1,
          -> { Profile.count } => 1, -> { LegacyReference.count } => 5
        ) do
          result = import([ row(id: 1) ])
        end

        assert_equal 1, result.reconciliation.count(:imported)

        user = resolved("user", 1)
        assert_kind_of User, user
        assert_equal user, resolved("identity_email", 1).user
        assert_equal @brand.id, resolved("membership", 1).brand_id
        assert_equal @brand.id, resolved("profile", 1).brand_id
      end

      test "the email identifier is normalized and takes verified_at from confirmed_at" do
        import([ row(id: 1, email: "Member1@Date9ja.Example", confirmed_at: Time.utc(2022, 5, 5)) ])

        identifier = resolved("identity_email", 1)
        assert_equal "member1@date9ja.example", identifier.normalized_value
        assert_equal Time.utc(2022, 5, 5), identifier.verified_at
      end

      test "imports a phone identifier through the canonical normalizer when present" do
        result = import([
          row(id: 1, phone: "+234 801 234 5678", phone_verified_at: Time.utc(2024, 3, 3))
        ])

        phone = resolved("identity_phone", 1)
        assert_equal "2348012345678", phone.normalized_value
        assert phone.phone?
        assert_equal Time.utc(2024, 3, 3), phone.verified_at
        assert_equal 2, result.reconciliation.to_h.dig("created", "identifiers_created")
        assert_equal 6, result.reconciliation.to_h.dig("created", "legacy_references_created")
      end

      test "copies the legacy bcrypt digest byte-for-byte and it authenticates unchanged" do
        digest = synthetic_digest
        import([ row(id: 1, encrypted_password: digest) ])

        credential = resolved("password_credential", 1)
        stored = CredentialPasswordHash.find(credential.id).password_hash

        assert_equal digest, stored
        assert_equal digest.b, stored.b
        assert_equal true,
          Identity::PasswordEngine.matches?(credential: credential, password: SYNTHETIC_PASSWORD)
        assert_equal false,
          Identity::PasswordEngine.matches?(credential: credential, password: "wrong-#{SYNTHETIC_PASSWORD}")
      end

      test "maps membership and profile lifecycle state" do
        import([ row(id: 1, suspended_at: Time.utc(2024, 6, 1), profile_hidden: true) ])

        assert_equal "suspended", resolved("membership", 1).status
        profile = resolved("profile", 1)
        assert_equal "suspended", profile.status
        assert_equal "hidden", profile.visibility
      end

      test "keeps an otherwise eligible profile unpublished until dependent slices complete" do
        import([ row(id: 1, onboarding_completed_at: Time.utc(2024, 2, 1), profile_hidden: false) ])

        profile = resolved("profile", 1)
        assert_equal "draft", profile.status
        assert_equal "hidden", profile.visibility
      end

      test "maps the approved non-sensitive profile fields" do
        import([ row(id: 1, display_name: "Ada", gender: "woman", city: "Abuja", country_of_residence: "NG") ])

        profile = resolved("profile", 1)
        assert_equal "Ada", profile.display_name
        assert_equal Date.new(1994, 6, 15), profile.birthdate
        assert_equal "woman", profile.gender
        assert_equal "Abuja", profile.city
        assert_equal "NG", profile.country_code
      end

      # --- idempotency -----------------------------------------------------

      test "a second run against the same source creates nothing new" do
        rows = [ row(id: 1), row(id: 2, phone: "+2348020000002") ]
        import(rows)

        counts = -> {
          [ User, IdentityIdentifier, Credential, CredentialPasswordHash,
            BrandMembership, Profile, LegacyReference ].map(&:count)
        }

        before = counts.call
        result = import(rows)

        assert_equal before, counts.call
        assert_equal 2, result.reconciliation.count(:already_imported)
        assert_equal 0, result.reconciliation.count(:imported)
      end

      test "a suspended imported row is also complete on rerun" do
        rows = [ row(id: 1, suspended_at: Time.utc(2024, 6, 1)) ]
        import(rows)

        result = import(rows)

        assert_equal 1, result.reconciliation.count(:already_imported)
        assert_equal 0, result.reconciliation.count(:failed)
      end

      # --- collisions ----------------------------------------------------

      test "a normalized-email collision fails the row closed and never merges" do
        existing = User.create!
        existing.identity_identifiers.create!(kind: :email, normalized_value: "member1@date9ja.example")

        result = nil
        assert_no_difference([ -> { User.count }, -> { LegacyReference.count } ]) do
          result = import([ row(id: 1) ])
        end

        assert_equal 0, result.reconciliation.count(:imported)
        assert_equal 1, result.reconciliation.count(:failed)
        assert_equal 1, result.reconciliation.reason_count("email_collision")
        assert_nil resolved("user", 1)
      end

      test "a normalized-phone collision imports the row without the phone identifier" do
        other = User.create!
        other.identity_identifiers.create!(kind: :phone, normalized_value: "2348012345678")

        result = import([ row(id: 1, phone: "+2348012345678") ])

        assert_equal 1, result.reconciliation.count(:imported)
        assert_nil resolved("identity_phone", 1)
        assert_equal 1, result.reconciliation.reason_count("phone_collision")
        assert_equal 1, result.reconciliation.to_h.dig("anomalies", "normalization_collisions")
      end

      # --- malformed / missing -----------------------------------------

      test "a missing/unparseable email fails the row" do
        result = nil
        assert_no_difference(-> { User.count }) do
          result = import([ row(id: 1, email: "not-an-email") ])
        end

        assert_equal 1, result.reconciliation.reason_count("email_unparseable")
        assert_equal 1, result.reconciliation.to_h.dig("anomalies", "missing_identifiers")
      end

      test "a malformed bcrypt digest fails the row closed" do
        result = nil
        assert_no_difference(-> { User.count }) do
          result = import([ row(id: 1, encrypted_password: "not-a-real-hash") ])
        end

        assert_equal 1, result.reconciliation.count(:failed)
        assert_equal 1, result.reconciliation.reason_count("credential_hash_unusable")
      end

      test "a blank bcrypt digest skips the row with a reason" do
        result = import([ row(id: 1, encrypted_password: "") ])

        assert_equal 1, result.reconciliation.count(:skipped)
        assert_equal 1, result.reconciliation.reason_count("credential_hash_unusable")
      end

      test "an underage / invalid profile fails the row and persists nothing" do
        result = nil
        assert_no_difference([ -> { User.count }, -> { LegacyReference.count } ]) do
          result = import([ row(id: 1, date_of_birth: (Time.zone.today - 10.years)) ])
        end

        assert_equal 1, result.reconciliation.count(:failed)
        assert_equal 1, result.reconciliation.reason_count("profile_invalid")
      end

      test "a soft-deleted or banned source row is skipped with a documented reason" do
        result = nil
        assert_no_difference(-> { User.count }) do
          result = import([
            row(id: 1, deleted_at: Time.utc(2024, 1, 1)),
            row(id: 2, banned_at: Time.utc(2024, 1, 1))
          ])
        end

        assert_equal 2, result.reconciliation.count(:skipped)
        assert_equal 1, result.reconciliation.reason_count("source_soft_deleted")
        assert_equal 1, result.reconciliation.reason_count("source_banned")
      end

      # --- binding / tenant safety --------------------------------------

      test "a dangling existing user binding fails closed" do
        throwaway = User.create!
        Migration::ReferenceMap.bind!(
          source_system: "date9ja", source_entity: "user", source_id: "1",
          destination: throwaway, importer_version: "date9ja-identity-v1"
        )
        throwaway.destroy!

        result = import([ row(id: 1) ])

        assert_equal 1, result.reconciliation.count(:failed)
        assert_equal 1, result.reconciliation.reason_count("dangling_binding")
        assert_equal 1, result.reconciliation.to_h.dig("anomalies", "binding_conflicts")
      end

      test "does not call a resolvable user binding complete when downstream state is missing" do
        user = User.create!
        Migration::ReferenceMap.bind!(
          source_system: "date9ja", source_entity: "user", source_id: "1",
          destination: user, importer_version: "date9ja-identity-v1"
        )

        result = import([ row(id: 1) ])

        assert_equal 1, result.reconciliation.count(:failed)
        assert_equal 1, result.reconciliation.reason_count("incomplete_binding")
        assert_equal 0, result.reconciliation.count(:already_imported)
      end

      test "the importer refuses a brand that is not the active date9ja brand" do
        other = Brand.create!(slug: "dateza", name: "DateZA", status: :active)
        assert_raises(IdentityImport::WrongBrand) do
          IdentityImport.call(brand: other, source: Snapshot::UserSource.new(rows: [ row(id: 1) ]))
        end

        @brand.update!(status: :disabled)
        assert_raises(IdentityImport::WrongBrand) do
          IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: [ row(id: 1) ]))
        end
      end

      # --- firewall -------------------------------------------------------

      test "sensitive legacy columns never cross the adapter boundary" do
        denied = FieldMapping::SENSITIVE_DENYLIST

        assert_empty(denied & Snapshot::UserSource::SELECTED_COLUMNS)
        assert_empty(denied & Snapshot::UserRecord.members.map(&:to_s))
        assert_empty(denied & Profile.column_names)

        # Even if a raw row carries a sensitive column, it is dropped on read.
        result = import([ row(id: 1).merge("tribe" => "some-value", "genotype" => "AA") ])
        assert_equal 1, result.reconciliation.count(:imported)
        refute_includes resolved("profile", 1).attributes.values.map(&:to_s), "AA"
      end

      # --- reconciliation ------------------------------------------------

      test "reconciliation totals reconcile with no unexplained loss" do
        result = import([
          row(id: 1),
          row(id: 2, deleted_at: Time.utc(2024, 1, 1)),
          row(id: 3, email: "bad"),
          row(id: 4, encrypted_password: "nope")
        ])

        h = result.reconciliation.to_h
        assert_equal 4, h["source_users_considered"]
        assert_equal 4, h["dispositions"].values.sum
        assert_equal({ "imported" => 1, "already_imported" => 0, "skipped" => 1, "failed" => 2 },
          h["dispositions"])
      end

      test "reconciliation output carries no PII or secret material" do
        digest = synthetic_digest
        User.create!.identity_identifiers.create!(kind: :email, normalized_value: "member9@date9ja.example")
        result = import([
          row(id: 9, encrypted_password: digest, phone: "+2348090000009", display_name: "Sensitive Name")
        ])

        dump = result.reconciliation.to_h.to_s
        [ digest, "member9@date9ja.example", "2348090000009", "Sensitive Name" ].each do |secret|
          refute_includes dump, secret
        end
      end
    end
  end
end
