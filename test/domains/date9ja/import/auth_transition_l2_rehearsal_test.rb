# frozen_string_literal: true

require "test_helper"
require "bcrypt"

module Date9ja
  module Import
    # Scaled, self-contained L2 rehearsal for Wave A Step 3 — the in-process
    # analogue of the operator `date9ja:verify_auth_transition` run (which needs
    # operator-owned real seed accounts + out-of-band plaintexts and stays an
    # operator task, like `scripts/date9ja/bcrypt_proof.rb`).
    #
    # Builds a synthetic `users` cohort spanning every migrated lifecycle and
    # every credential edge, imports it through the REAL `IdentityImport`, proves
    # the reconciliation balances and is idempotent, then drives every migrated
    # account through the whole signed-out auth journey with `AuthTransitionCheck`.
    #
    # SYNTHETIC ENGINEERING EVIDENCE ONLY (bcrypt MIN_COST). Real cost-12 digest
    # compatibility is VERIFIED separately (`bcrypt_proof.rb`, `$2a$ 12 PASS`).
    # Slow-ish (~30-60s: ~20 accounts each doing real recovery/reset bcrypt work).
    class AuthTransitionL2RehearsalTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(
          slug: "date9ja", name: "Date9ja", status: :active,
          auth_methods: %w[email_password phone_password]
        )
        @isolation_brand = Brand.create!(slug: "dateza", name: "DateZA", status: :active)
      end

      def digest_for(password) = BCrypt::Password.create(password, cost: BCrypt::Engine::MIN_COST).to_s

      def base_row(id, **overrides)
        {
          "id" => id, "public_id" => "pub-#{id}",
          "email" => "u#{id}@date9ja.example", "phone" => nil,
          "encrypted_password" => digest_for("pw-#{id}-passphrase"),
          "confirmed_at" => Time.utc(2024, 1, 1), "phone_verified_at" => nil,
          "created_at" => Time.utc(2023, 1, 1), "deleted_at" => nil,
          "suspended_at" => nil, "banned_at" => nil, "profile_hidden" => false,
          "onboarding_completed_at" => Time.utc(2024, 2, 1),
          "date_of_birth" => Date.new(1993, 3, 3), "gender" => "man", "display_name" => "U#{id}",
          "city" => "Lagos", "country_of_residence" => "NG", "about_me" => "x", "ideal_partner_description" => "y"
        }.merge(overrides.transform_keys(&:to_s))
      end

      # cohort: [row, subject-or-nil, expected-disposition]
      def cohort
        rows = []

        # 8 plain active accounts (email, confirmed) — full recovery + reactivation
        (1..8).each { |id| rows << [ base_row(id), sub(id, :active), :imported ] }

        # 2 active with a verified phone as well (recovery still via email here)
        [ 9, 10 ].each do |id|
          rows << [ base_row(id, phone: "+23480200000#{id}", phone_verified_at: Time.utc(2024, 1, 2)),
                    sub(id, :active), :imported ]
        end

        # 2 active whose email is UNCONFIRMED and no phone — login works on the
        # password, signed-out recovery legitimately unavailable (ADR 0012).
        [ 11, 12 ].each do |id|
          rows << [ base_row(id, confirmed_at: nil), sub(id, :active, recovery_expected: false), :imported ]
        end

        # 2 recovery-required: unusable digest + confirmed email
        [ 13, 14 ].each do |id|
          rows << [ base_row(id, encrypted_password: id.even? ? "" : "not-bcrypt"),
                    sub(id, :recovery_required, password: nil), :imported ]
        end

        # 2 suspended (valid digest)
        [ 15, 16 ].each do |id|
          rows << [ base_row(id, suspended_at: Time.utc(2024, 6, 1)), sub(id, :suspended), :imported ]
        end

        # non-imported rows (not exercised by AuthTransitionCheck)
        rows << [ base_row(17, banned_at: Time.utc(2024, 1, 1)), nil, :skipped ]
        rows << [ base_row(18, deleted_at: Time.utc(2024, 1, 1)), nil, :skipped ]
        rows << [ base_row(19, encrypted_password: "nope", confirmed_at: nil, phone_verified_at: nil), nil, :failed ]

        rows
      end

      def sub(id, lifecycle, password: "pw-#{id}-passphrase", recovery_expected: true)
        AuthTransitionCheck::Subject.build(
          source_ref: id.to_s, identifier: "u#{id}@date9ja.example",
          password:, digest: nil, lifecycle:, recovery_expected:
        )
      end

      test "full synthetic cohort imports, reconciles, is idempotent, and passes the whole auth journey" do
        rows = cohort
        source_rows = rows.map(&:first)

        # --- import + reconciliation balance ---
        first = IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: source_rows))
        h = first.reconciliation.to_h
        assert_equal source_rows.size, h["source_users_considered"]
        assert_equal source_rows.size, h["dispositions"].values.sum, "no unexplained rows"
        assert_equal rows.count { |_, _, d| d == :imported }, h["dispositions"]["imported"]
        assert_equal rows.count { |_, _, d| d == :skipped }, h["dispositions"]["skipped"]
        assert_equal rows.count { |_, _, d| d == :failed }, h["dispositions"]["failed"]
        assert_equal 2, first.reconciliation.reason_count("credential_recovery_required")
        assert_equal 2, h.dig("created", "credentials_recovery_required")
        assert_equal 14, h.dig("created", "password_hashes_created") # 16 imported - 2 recovery-required

        # --- idempotency: a clean re-run BEFORE anyone signs in ---
        counts = -> { [ User, IdentityIdentifier, Credential, CredentialPasswordHash, BrandMembership, Profile, LegacyReference ].map(&:count) }
        before = counts.call
        second = IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: source_rows))
        assert_equal before, counts.call, "re-run created/destroyed nothing"
        assert_equal 16, second.reconciliation.count(:already_imported)
        assert_equal 0, second.reconciliation.count(:imported)
        assert_equal({ "imported" => 0, "already_imported" => 16, "skipped" => 2, "failed" => 1 },
          second.reconciliation.to_h["dispositions"])

        # --- whole auth journey for every migrated account ---
        subjects = rows.filter_map { |_, s, _| s }
        result = AuthTransitionCheck.call(brand: @brand, subjects:, isolation_brand: @isolation_brand)
        assert result.all_passed?, "auth journey failures: #{result.reconciliation.to_h}"

        rh = result.reconciliation.to_h
        assert_equal 16, rh["subjects_considered"]
        assert_equal 0, rh["failures"]
        assert_equal({ "active" => 12, "recovery_required" => 2, "suspended" => 2 }, rh["lifecycles"])
        assert_equal 12, rh.dig("checks", "reactivation_roundtrip", "pass")
        assert_equal 12, rh.dig("checks", "recovery_roundtrip", "pass")       # 10 active-with-channel + 2 recovery-required
        assert_equal 2, rh.dig("checks", "recovery_unavailable_fails_closed", "pass")
        assert_equal 12, rh.dig("checks", "cross_brand_rejected", "pass")
        assert_equal 12, rh.dig("checks", "logout_revokes_session", "pass")
        assert_equal 2, rh.dig("checks", "no_residual_session", "pass")       # suspended

        # --- re-run AFTER members have reset passwords: still fails closed, no clobber, no loss ---
        after_use = counts.call
        third = IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: source_rows))
        assert_equal after_use, counts.call, "post-use re-run never clobbers a member-set password"
        assert_equal 0, third.reconciliation.count(:imported)
        assert_equal 16, third.reconciliation.count(:already_imported)

        # --- PII-free ---
        [ first.reconciliation.to_h, result.reconciliation.to_h ].each do |dump|
          s = dump.to_s
          %w[u1@date9ja.example pw-1-passphrase recovered-passphrase-9ja $2a$].each { |secret| refute_includes s, secret }
        end
      end
    end
  end
end
