# frozen_string_literal: true

require "test_helper"
require "bcrypt"

module Date9ja
  module Import
    # D8N contract-fidelity pass: every non-sensitive Date9ja profile/preference
    # value a member holds is represented and preserved in D8N. These tests cover
    # the enrichment SCALARS (the option groups are covered in
    # profile_preference_import_test) plus the invariants: gap-fill only,
    # non-destructive rerun, never a publication gate, other brands unchanged.
    class ContractFidelityTest < ActiveSupport::TestCase
      setup do
        @brand = Brands::Date9jaInstaller.call
        Geography::NigeriaCatalog.install!
      end

      def row(id:, **overrides)
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

      def run_all(rows)
        IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows:))
        ProfilePreferenceImport.call(brand: @brand, source: Snapshot::UserSource.new(rows:))
        ProfileReadinessImport.call(
          brand: @brand, source: Snapshot::UserSource.new(rows:),
          publication_policy: :publish_visible_onboarded
        )
      end

      def profile_for(id)
        Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile", source_id: id.to_s)
      end

      test "lifestyle-frequency scalars are decoded and written" do
        run_all([ row(id: 1, smoking: 0, drinking: 1, fitness: 2) ])
        profile = profile_for(1).reload
        assert_equal "never", profile.smoking
        assert_equal "occasionally", profile.drinking
        assert_equal "regularly", profile.fitness
      end

      test "body type is preserved verbatim, never coerced onto an enum" do
        run_all([ row(id: 1, body_type: "  broad  shouldered ") ])
        assert_equal "broad shouldered", profile_for(1).reload.body_type
      end

      test "occupation is preserved verbatim within the field length" do
        run_all([ row(id: 1, occupation: "Software Engineer") ])
        assert_equal "Software Engineer", profile_for(1).reload.occupation
      end

      test "height inside a plausible band migrates; junk is quarantined, not written" do
        run_all([
          row(id: 1, height: 178),
          row(id: 2, height: 588, email: "b@example.test"),
          row(id: 3, height: 1, email: "c@example.test")
        ])
        assert_equal 178, profile_for(1).reload.height_cm
        assert_nil profile_for(2).reload.height_cm
        assert_nil profile_for(3).reload.height_cm
      end

      test "willing_to_relocate keeps the source tri-state" do
        run_all([
          row(id: 1, willing_to_relocate: true),
          row(id: 2, willing_to_relocate: false, email: "b@example.test"),
          row(id: 3, willing_to_relocate: nil, email: "c@example.test")
        ])
        assert_equal true, profile_for(1).reload.willing_to_relocate
        assert_equal false, profile_for(2).reload.willing_to_relocate
        assert_nil profile_for(3).reload.willing_to_relocate
      end

      test "languages map through the explicit table; unknown names stay unmapped" do
        run_all([ row(id: 1, languages_spoken: [ "English", "Yoruba", "Nigerian Pidgin" ]) ])
        codes = profile_for(1).reload.languages.map { |entry| entry["code"] }
        assert_equal %w[en yo], codes
        assert(profile_for(1).languages.all? { |entry| entry["proficiency"].nil? && !entry["primary"] })
      end

      test "relocation_preferences array is carried as normalized free text" do
        run_all([ row(id: 1, relocation_preferences: [ "  Lagos ", "Abuja", "Lagos" ]) ])
        assert_equal [ "Lagos", "Abuja" ], profile_for(1).reload.relocation_preferences
      end

      test "preferred_countries decodes to ISO codes on the preference" do
        run_all([ row(id: 1, preferred_countries: [ "Nigeria", "Ghana" ]) ])
        assert_equal %w[NG GH], profile_for(1).reload.profile_preference.preferred_country_codes
      end

      def selection_codes(id, group_key)
        group = @brand.profile_option_groups.kept.find_by!(key: group_key)
        ProfileOptionSelection.kept.where(profile: profile_for(id), profile_option_group: group)
          .joins(:profile_option).pluck("profile_options.code").sort
      end

      test "interests / relationship_values / dealbreakers map to curated multi-selections" do
        run_all([ row(id: 1,
          interests: [ "Afrobeats", "Football", "Cooking" ],
          relationship_values: [ "Honesty", "Family", "Ambition" ],
          dealbreakers: [ "Smoking", "Long distance" ]) ])

        assert_equal %w[afrobeats cooking football], selection_codes(1, "interests")
        assert_equal %w[ambition family honesty], selection_codes(1, "relationship_values")
        assert_equal %w[long_distance smoking], selection_codes(1, "dealbreakers")
      end

      test "an unmappable taxonomy element is quarantined, never guessed" do
        result = run_all([ row(id: 1, interests: [ "Afrobeats", "underwater basket weaving" ]) ])
        assert_equal %w[afrobeats], selection_codes(1, "interests")
        assert_equal 1, result.reconciliation.to_h.dig("measures", "interests_mapped")
      end

      test "a rerun does not overwrite taxonomy selections the member edited" do
        rows = [ row(id: 1, interests: [ "Football" ]) ]
        run_all(rows)
        group = @brand.profile_option_groups.kept.find_by!(key: "interests")
        ProfileOptionSelection.kept.where(profile: profile_for(1), profile_option_group: group).delete_all
        gym = group.profile_options.kept.find_by!(code: "gym")
        ProfileOptionSelection.create!(profile: profile_for(1), user_id: profile_for(1).user_id,
          brand_id: @brand.id, profile_option_group: group, profile_option: gym)

        run_all(rows)

        assert_equal %w[gym], selection_codes(1, "interests")
      end

      test "a migrated member with no taxonomy values still publishes and records nothing" do
        result = run_all([ row(id: 1, interests: [], relationship_values: [], dealbreakers: []) ])
        assert_equal 1, result.reconciliation.count(:ready)
        assert_equal 0, result.reconciliation.to_h.dig("measures", "interests_mapped")
        assert_empty selection_codes(1, "relationship_values")
      end

      test "a rerun does not overwrite relocation_preferences the member edited" do
        rows = [ row(id: 1, relocation_preferences: [ "Lagos" ]) ]
        run_all(rows)
        profile_for(1).reload.update!(relocation_preferences: [ "Cape Town" ])

        run_all(rows)

        assert_equal [ "Cape Town" ], profile_for(1).reload.relocation_preferences
      end

      test "a rerun does not overwrite a value the member changed after migration" do
        rows = [ row(id: 1, smoking: 0, body_type: "athletic") ]
        run_all(rows)
        profile = profile_for(1).reload
        profile.update!(smoking: "regularly", body_type: "curvy")

        run_all(rows)

        profile.reload
        assert_equal "regularly", profile.smoking
        assert_equal "curvy", profile.body_type
      end

      test "a value this importer set and the member then cleared is not refilled" do
        rows = [ row(id: 1, smoking: 1) ]
        run_all(rows)
        profile_for(1).reload.update!(smoking: nil)

        run_all(rows)

        assert_nil profile_for(1).reload.smoking
      end

      test "a migrated member with none of the enrichment values still publishes" do
        rows = [ row(id: 1,
          smoking: nil, drinking: nil, fitness: nil, body_type: nil, height: nil,
          occupation: nil, willing_to_relocate: nil, languages_spoken: [],
          relationship_intention: nil, wants_children: nil, children_count: nil,
          family_involvement_preference: nil, commitment_timeline: nil,
          marital_status: nil, education: nil) ]
        result = run_all(rows)

        assert_equal 1, result.reconciliation.count(:ready)
        profile = profile_for(1).reload
        assert profile.active?
        assert profile.visible?
      end

      test "other brands' shared option groups are unchanged by the new codes" do
        dateza = Brands::DatezaInstaller.call
        hookus = Brands::HookusInstaller.call

        [ dateza, hookus ].each do |brand|
          wants = brand.profile_option_groups.kept.find_by!(key: "wants_children")
          assert_equal %w[yes maybe no open_to_partner_with_children prefer_not_to_say],
            wants.profile_options.kept.order(:position).pluck(:code)
          education = brand.profile_option_groups.kept.find_by!(key: "education_level")
          assert_not_includes education.profile_options.kept.pluck(:code), "diploma"
        end

        # DateZA offers relationship_intent from its own curated list only.
        dateza_intents = dateza.profile_option_groups.kept.find_by!(key: "relationship_intent")
          .profile_options.kept.pluck(:code)
        assert_not_includes dateza_intents, "courtship"
        assert_not_includes dateza_intents, "activity_partner"
      end

      test "Date9ja offers every legacy relationship intention" do
        intents = @brand.profile_option_groups.kept.find_by!(key: "relationship_intent")
          .profile_options.kept.pluck(:code)
        assert (%w[marriage courtship long_term_relationship dating friendship activity_partner] - intents).empty?
      end
    end
  end
end
