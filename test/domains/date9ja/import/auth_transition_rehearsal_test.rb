# frozen_string_literal: true

require "test_helper"
require "bcrypt"

module Date9ja
  module Import
    # L1 synthetic rehearsal for Wave A Step 3 — migrated-account authentication
    # transition + recovery/reactivation. Imports synthetic Date9ja `users` rows
    # through the REAL `IdentityImport`, then drives every migrated account through
    # the shared D8N Identity services with `AuthTransitionCheck`.
    #
    # bcrypt cost is MIN_COST here (synthetic values only). The real cost-12
    # digest compatibility is separately VERIFIED by `scripts/date9ja/bcrypt_proof.rb`.
    class AuthTransitionRehearsalTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(
          slug: "date9ja", name: "Date9ja", status: :active,
          auth_methods: %w[email_password phone_password]
        )
        @isolation_brand = Brand.create!(slug: "dateza", name: "DateZA", status: :active)
      end

      def digest_for(password)
        BCrypt::Password.create(password, cost: BCrypt::Engine::MIN_COST).to_s
      end

      def row(id:, password: "battery-horse-#{id}", **overrides)
        {
          "id" => id, "public_id" => "pub-#{id}",
          "email" => "member#{id}@date9ja.example", "phone" => nil,
          "encrypted_password" => digest_for(password),
          "confirmed_at" => Time.utc(2024, 1, 1), "phone_verified_at" => nil,
          "created_at" => Time.utc(2023, 1, 1), "deleted_at" => nil,
          "suspended_at" => nil, "banned_at" => nil, "profile_hidden" => false,
          "onboarding_completed_at" => Time.utc(2024, 2, 1),
          "date_of_birth" => Date.new(1994, 6, 15), "gender" => "woman",
          "display_name" => "Member #{id}", "city" => "Lagos",
          "country_of_residence" => "NG", "about_me" => "hello", "ideal_partner_description" => "kind"
        }.merge(overrides.transform_keys(&:to_s))
      end

      def import(rows)
        IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: rows))
      end

      def subject(id, lifecycle:, password: "battery-horse-#{id}", digest: nil, recovery_expected: true)
        AuthTransitionCheck::Subject.build(
          source_ref: id.to_s, identifier: "member#{id}@date9ja.example",
          password:, digest:, lifecycle:, recovery_expected:
        )
      end

      test "every migrated account authenticates, recovers and reactivates through the shared D8N services" do
        digests = { 1 => digest_for("battery-horse-1"), 2 => digest_for("battery-horse-2"),
                    3 => digest_for("battery-horse-3") }
        rows = [
          row(id: 1, encrypted_password: digests[1]),
          row(id: 2, encrypted_password: digests[2]),
          row(id: 3, encrypted_password: digests[3], suspended_at: Time.utc(2024, 6, 1)),
          # unusable legacy digest + verified email -> recovery-required account
          row(id: 4, encrypted_password: "not-a-bcrypt-string")
        ]

        import_result = import(rows)
        recon = import_result.reconciliation.to_h
        assert_equal 4, recon["source_users_considered"]
        assert_equal 4, recon["dispositions"]["imported"]
        assert_equal 1, import_result.reconciliation.reason_count("credential_recovery_required")
        assert_equal 1, recon.dig("created", "credentials_recovery_required")
        assert_equal 3, recon.dig("created", "password_hashes_created")

        subjects = [
          subject(1, lifecycle: :active, digest: digests[1]),
          subject(2, lifecycle: :active, digest: digests[2]),
          subject(3, lifecycle: :suspended),
          subject(4, lifecycle: :recovery_required, password: nil)
        ]

        result = AuthTransitionCheck.call(
          brand: @brand, subjects:, isolation_brand: @isolation_brand
        )

        assert result.all_passed?, "auth transition checks failed: #{result.reconciliation.to_h}"
        h = result.reconciliation.to_h
        assert_equal 4, h["subjects_considered"]
        assert_equal 0, h["failures"]
        assert_equal({ "active" => 2, "recovery_required" => 1, "suspended" => 1 }, h["lifecycles"])
        assert h.dig("checks", "recovery_roundtrip", "pass") >= 3
        assert h.dig("checks", "reactivation_roundtrip", "pass") == 2
        assert h.dig("checks", "cross_brand_rejected", "pass") == 2
      end

      test "an unusable legacy digest with no verified channel fails closed, not silently lost" do
        result = import([ row(id: 9, encrypted_password: "nope", confirmed_at: nil, phone_verified_at: nil) ])

        assert_equal 1, result.reconciliation.count(:failed)
        assert_equal 1, result.reconciliation.reason_count("credential_hash_unusable")
        assert_nil Migration::ReferenceMap.resolve(
          source_system: "date9ja", source_entity: "user", source_id: "9"
        )
      end

      test "parse_manifest rejects an empty manifest and unknown lifecycles, accepts a valid one" do
        assert_raises(AuthTransitionCheck::ManifestError) { AuthTransitionCheck.parse_manifest([]) }
        assert_raises(AuthTransitionCheck::ManifestError) { AuthTransitionCheck.parse_manifest([ "# only a comment\n", "\n" ]) }

        err = assert_raises(AuthTransitionCheck::ManifestError) do
          AuthTransitionCheck.parse_manifest([ "a@b.example\tsecretpw\tsuper_admin\n" ])
        end
        assert_includes err.message, "unknown lifecycle"
        refute_includes err.message, "secretpw"
        refute_includes err.message, "a@b.example"

        subjects = AuthTransitionCheck.parse_manifest([
          "# operator manifest\n",
          "a1@date9ja.example\talpha-pass\tactive\n",
          "a2@date9ja.example\t\trecovery_required\n",
          "a3@date9ja.example\tgamma-pass\tactive\tno_recovery\n",
          "a4@date9ja.example\tdelta-pass\tsuspended\n"
        ])
        assert_equal %i[active recovery_required active suspended], subjects.map(&:lifecycle)
        assert_nil subjects[1].password
        assert_equal false, subjects[2].recovery_expected
      end

      test "an unknown lifecycle is a failure, and a zero-subject run is not a pass" do
        empty = AuthTransitionCheck.call(brand: @brand, subjects: [])
        refute empty.all_passed?

        bad = AuthTransitionCheck::Subject.build(source_ref: "x", identifier: "x@y.example", lifecycle: :bogus)
        result = AuthTransitionCheck.call(brand: @brand, subjects: [ bad ])
        refute result.all_passed?
        assert_equal 1, result.reconciliation.to_h.dig("checks", "lifecycle_supported", "fail")
      end

      test "the rehearsal reconciliation carries no PII or secret material" do
        import([ row(id: 1, password: "battery-horse-1") ])
        result = AuthTransitionCheck.call(
          brand: @brand,
          subjects: [ subject(1, lifecycle: :active) ],
          isolation_brand: @isolation_brand
        )

        dump = result.reconciliation.to_h.to_s
        [ "member1@date9ja.example", "battery-horse-1", "recovered-passphrase-9ja", "$2a$" ].each do |secret|
          refute_includes dump, secret
        end
      end
    end
  end
end
