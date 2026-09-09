# frozen_string_literal: true

require "test_helper"
require "bcrypt"

module Date9ja
  module Import
    # The gated sensitive-profile importer: religion / tribe / ethnicity /
    # denomination / genotype / state_of_origin / nationality / is_nigerian /
    # openness flags / matching-preference arrays / interest_in_nigerian_culture.
    class SensitiveProfileImportTest < ActiveSupport::TestCase
      setup do
        @brand = Brands::Date9jaInstaller.call
        Geography::NigeriaCatalog.install!
      end

      def base_row(id:, **overrides)
        {
          id:, public_id: "pub-#{id}", email: "member#{id}@example.test", phone: nil,
          encrypted_password: BCrypt::Password.create("x", cost: BCrypt::Engine::MIN_COST).to_s,
          confirmed_at: Time.utc(2024, 1, 1), phone_verified_at: nil, created_at: Time.utc(2023, 1, 1),
          deleted_at: nil, suspended_at: nil, banned_at: nil, profile_hidden: false,
          onboarding_completed_at: Time.utc(2024, 2, 1), date_of_birth: 30.years.ago.to_date,
          gender: 0, full_name: "Tunde Okafor", display_name: "Member #{id}", city: "Lagos",
          country_of_residence: "Nigeria", about_me: "A real biography", ideal_partner_description: "Kind",
          looking_for: 1, preferred_age_min: 25, preferred_age_max: 40, preferred_distance_km: nil,
          relationship_intention: 0, wants_children: 0, children_count: 0
        }.merge(overrides)
      end

      # Runs identity + preference first so a Profile and ProfilePreference exist,
      # then the sensitive pass over the same source ids.
      def run_sensitive(base_rows, sensitive_rows)
        IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: base_rows))
        ProfilePreferenceImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: base_rows))
        SensitiveProfileImport.call(
          brand: @brand, source: Snapshot::SensitiveUserSource.new(rows: sensitive_rows)
        )
      end

      def profile_for(id)
        Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile", source_id: id.to_s)
      end

      def selection(id, group_key)
        group = @brand.profile_option_groups.kept.find_by!(key: group_key)
        ProfileOptionSelection.kept.where(profile: profile_for(id), profile_option_group: group)
          .joins(:profile_option).pluck("profile_options.code")
      end

      test "preserves scalars, option groups and matching preferences, all owner-only" do
        result = run_sensitive(
          [ base_row(id: 1) ],
          [ { id: 1, is_nigerian: true, state_of_origin: "Imo", nationality: "Nigeria",
              tribe: "Igbo", ethnicity: "Igbo", religion: "Christianity", denomination: "Catholic",
              genotype: "AS", intertribal_marriage_openness: "open", polygamy_openness: "no",
              interest_in_nigerian_culture: "Very involved in my culture",
              preferred_religion: [ "Christianity" ], preferred_tribes: [ "Igbo", "Yoruba" ],
              preferred_ethnicity: [], preferred_genotype: [ "AA", "AS" ] } ]
        )

        profile = profile_for(1).reload
        assert_equal true, profile.is_nigerian
        assert_equal "Imo", profile.state_of_origin
        assert_equal "NG", profile.nationality
        assert_equal "Very involved in my culture", profile.interest_in_nigerian_culture
        assert_equal [ "igbo" ], selection(1, "tribe")
        assert_equal [ "christian" ], selection(1, "religion")
        assert_equal [ "catholic" ], selection(1, "denomination")
        assert_equal [ "as" ], selection(1, "genotype")
        assert_equal [ "open" ], selection(1, "intertribal_marriage_openness")
        assert_equal [ "not_open" ], selection(1, "polygamy_openness")

        preference = ProfilePreference.kept.find_by!(profile: profile_for(1))
        assert_equal({ "religion" => [ "christian" ], "tribe" => [ "igbo", "yoruba" ],
                       "genotype" => [ "aa", "as" ] }, preference.preferred_attributes)

        assert_equal 1, result.reconciliation.count(:imported)
        assert result.reconciliation.balanced?
      end

      test "an unrecognised sensitive value is quarantined and noted, never guessed" do
        result = run_sensitive(
          [ base_row(id: 1) ],
          [ { id: 1, tribe: "Martian", state_of_origin: "Atlantis", religion: nil } ]
        )

        assert_empty selection(1, "tribe")
        assert_nil profile_for(1).reload.state_of_origin
        assert_equal 1, result.reconciliation.note_count("tribe_unmapped")
        assert_equal 1, result.reconciliation.note_count("state_of_origin_unmapped")
        assert_equal 1, result.reconciliation.note_count("religion_absent")
      end

      test "gap-fill only: a member's own sensitive value survives a rerun" do
        rows = [ { id: 1, tribe: "Igbo", is_nigerian: true } ]
        run_sensitive([ base_row(id: 1) ], rows)

        profile = profile_for(1)
        group = @brand.profile_option_groups.kept.find_by!(key: "tribe")
        ProfileOptionSelection.kept.where(profile:, profile_option_group: group).delete_all
        yoruba = group.profile_options.kept.find_by!(code: "yoruba")
        ProfileOptionSelection.create!(profile:, user_id: profile.user_id, brand_id: @brand.id,
          profile_option_group: group, profile_option: yoruba)
        profile.update!(is_nigerian: false)

        result = SensitiveProfileImport.call(
          brand: @brand, source: Snapshot::SensitiveUserSource.new(rows: rows)
        )

        assert_equal [ "yoruba" ], selection(1, "tribe")
        assert_equal false, profile_for(1).reload.is_nigerian
        assert_equal 1, result.reconciliation.count(:imported)
      end

      test "the sanitized rehearsal shape (all NULL / empty) writes nothing" do
        result = run_sensitive([ base_row(id: 1) ], [ { id: 1 } ])

        profile = profile_for(1).reload
        assert_nil profile.is_nigerian
        assert_nil profile.state_of_origin
        assert_empty selection(1, "religion")
        assert_equal 0, result.reconciliation.to_h.dig("created", "option_selections_created")
        assert_equal 1, result.reconciliation.count(:imported)
        assert_equal 1, result.reconciliation.note_count("religion_absent")
      end

      test "a soft-deleted or banned source row is skipped" do
        result = run_sensitive(
          [ base_row(id: 1), base_row(id: 2, email: "b@example.test") ],
          [ { id: 1, deleted_at: Time.utc(2025, 1, 1), tribe: "Igbo" },
            { id: 2, banned_at: Time.utc(2025, 1, 1), tribe: "Yoruba" } ]
        )
        assert_equal 2, result.reconciliation.count(:skipped)
        assert result.reconciliation.balanced?
      end

      test "every sensitive destination stays owner-only" do
        %w[tribe ethnicity religion denomination genotype
           intertribal_marriage_openness polygamy_openness].each do |key|
          group = @brand.profile_option_groups.kept.find_by!(key:)
          assert_equal "owner_only", group.visibility, key
        end
        assert_equal :owner_only, Profiles::FieldCatalog.fetch("interest_in_nigerian_culture").default_audience
      end
    end
  end
end
