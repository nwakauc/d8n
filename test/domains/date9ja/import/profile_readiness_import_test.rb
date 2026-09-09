# frozen_string_literal: true

require "test_helper"
require "bcrypt"

module Date9ja
  module Import
    class ProfileReadinessImportTest < ActiveSupport::TestCase
      setup do
        @brand = Brands::Date9jaInstaller.call
        Geography::NigeriaCatalog.install!
      end

      test "a fully resolvable source member reaches canonical publication and matching eligibility" do
        rows = [
          row(id: 1, full_name: "Tunde Okafor", gender: 0, looking_for: 1),
          row(id: 2, full_name: "Ada Nwosu", gender: 1, looking_for: 0,
            email: "ada@example.test", date_of_birth: 28.years.ago.to_date)
        ]
        import_identity_and_preferences(rows)
        rows.each { |source_row| attach_ready_photo(profile_for(source_row.fetch(:id))) }

        result = readiness(rows, publication_policy: :publish_visible_onboarded)

        assert_equal 2, result.reconciliation.count(:ready)
        assert result.reconciliation.balanced?
        rows.each do |source_row|
          profile = profile_for(source_row.fetch(:id)).reload
          assert Profiles::Completion.call(profile:).complete?
          assert profile.active?
          assert profile.visible?
          assert Migration::ProfileReadiness.find_by!(profile:).disposition_ready?
          assert_equal "NG", profile.country_code
          # Date9ja declares no place-selection capability: country/city are
          # profile scalars and readiness never creates a ProfileLocation.
          assert_not ProfileLocation.kept.exists?(profile:)
        end

        viewer = profile_for(1)
        candidate = profile_for(2)
        scope = Matching::EligibilityScope.call(
          brand: @brand, viewer:,
          policy: D8n::Platform::Brands::Date9ja::ELIGIBILITY_POLICY
        )
        assert_includes scope, candidate
      end

      test "one-token and three-token names map to a given name without fabricating a surname" do
        rows = [
          row(id: 1, full_name: "Madonna"),
          row(id: 2, full_name: "Ada Obi Nwosu", email: "ada@example.test")
        ]
        import_identity_and_preferences(rows)

        readiness(rows)

        madonna = profile_for(1).user
        assert_equal "Madonna", madonna.first_name
        assert_nil madonna.last_name, "a single-token name gets no fabricated surname"

        ada = profile_for(2).user
        assert_equal "Ada", ada.first_name
        assert_equal "Obi Nwosu", ada.last_name, "no token is discarded"
      end

      test "an unresolved country does not block a migrated member and is never guessed" do
        source_row = row(id: 1, country_of_residence: "Atlantis")
        import_identity_and_preferences([ source_row ])
        attach_ready_photo(profile_for(1))

        result = readiness([ source_row ], publication_policy: :publish_visible_onboarded)

        # Country is profile enrichment, not a Date9ja visibility gate. The
        # importer still refuses to guess an unknown value.
        assert_equal 1, result.reconciliation.count(:ready)
        assert_nil profile_for(1).country_code
        assert_equal 1, result.reconciliation.to_h.dig("measures", "countries_unresolved")
      end

      test "an unresolved city never creates a fake location or coordinates" do
        source_row = row(id: 1, city: "Owerri")
        import_identity_and_preferences([ source_row ])

        readiness([ source_row ])

        # Date9ja declares no place-selection capability, so readiness never
        # creates a ProfileLocation (fabricated or resolved) and location is not
        # a completion/discovery gate — there is no location remediation reason.
        assert_not ProfileLocation.kept.exists?(profile: profile_for(1))
        result = Migration::ProfileReadiness.find_by!(profile: profile_for(1))
        assert_not_includes result.reason_codes, "location_confirmation_required"
      end

      test "missing and partial age preferences remain unset and are never fabricated" do
        rows = [
          row(id: 1, preferred_age_min: nil, preferred_age_max: nil),
          row(id: 2, preferred_age_min: 25, preferred_age_max: nil, email: "ada@example.test")
        ]
        import_identity_and_preferences(rows)

        result = readiness(rows)

        # Liquidity-first: age preferences are not a Date9ja completion or
        # discovery gate, so a missing bound is not a remediation reason. The
        # importer still never invents a value.
        assert_equal 0, result.reconciliation.reason_count("age_preference_required")
        rows.each do |source_row|
          preference = profile_for(source_row.fetch(:id)).profile_preference
          assert_nil preference.min_age
          assert_nil preference.max_age
        end
      end

      test "an unmapped source option is left unset and does not block a migrated member" do
        source_row = row(id: 1, relationship_intention: 1)
        import_identity_and_preferences([ source_row ])
        attach_ready_photo(profile_for(1))

        result = readiness([ source_row ], publication_policy: :publish_visible_onboarded)

        # `courtship` (1) has no approved D8N mapping. It is never coerced onto a
        # near option, and — since option groups are not a Date9ja visibility
        # gate — its absence does not hold the member back.
        assert_equal 1, result.reconciliation.count(:ready)
        assert_equal 1, result.reconciliation.to_h.dig("measures", "relationship_intent_unresolved")
        group = ProfileOptionGroup.kept.find_by!(brand: @brand, key: "relationship_intent")
        assert_not ProfileOptionSelection.kept.exists?(profile: profile_for(1), profile_option_group: group)
      end

      test "an explicitly hidden complete legacy member stays intentionally hidden" do
        source_row = row(id: 1, profile_hidden: true)
        import_identity_and_preferences([ source_row ])
        attach_ready_photo(profile_for(1))

        result = readiness([ source_row ], publication_policy: :publish_visible_onboarded)

        profile = profile_for(1).reload
        assert_equal 1, result.reconciliation.count(:intentionally_hidden)
        assert profile.draft?
        assert profile.hidden?
        assert_includes Migration::ProfileReadiness.find_by!(profile:).reason_codes, "legacy_profile_hidden"
      end

      test "a suspended complete member is never published" do
        source_row = row(id: 1, suspended_at: Time.current)
        import_identity_and_preferences([ source_row ])
        attach_ready_photo(profile_for(1))

        result = readiness([ source_row ], publication_policy: :publish_visible_onboarded)

        profile = profile_for(1).reload
        assert_equal 1, result.reconciliation.count(:intentionally_hidden)
        assert profile.suspended?
        assert profile.hidden?
        assert_includes Migration::ProfileReadiness.find_by!(profile:).reason_codes, "source_suspended"
      end

      test "a source member banned after an earlier import is unpublished defensively" do
        source_row = row(id: 1)
        import_identity_and_preferences([ source_row ])
        attach_ready_photo(profile_for(1))
        readiness([ source_row ], publication_policy: :publish_visible_onboarded)
        assert profile_for(1).reload.visible?

        banned_row = source_row.merge(banned_at: Time.current)
        result = readiness([ banned_row ], publication_policy: :publish_visible_onboarded)

        assert_equal 1, result.reconciliation.to_h.dig("measures", "source_ineligible")
        assert_equal 0, result.reconciliation.to_h.dig("measures", "ineligible_suppression_failed")
        profile = profile_for(1).reload
        assert profile.hidden?
        assert profile.draft?
        evidence = Migration::ProfileReadiness.find_by!(profile:)
        assert evidence.disposition_intentionally_hidden?
        assert_equal [ "source_banned" ], evidence.reason_codes
      end

      test "reruns preserve member and operator values including a later unpublish" do
        source_row = row(id: 1)
        import_identity_and_preferences([ source_row ])
        profile = profile_for(1)
        attach_ready_photo(profile)

        user = profile.user
        user.update!(first_name: "Member", last_name: "Chosen")
        profile.update!(country_code: "ZA", city: "Cape Town")
        location = ProfileLocation.create!(
          profile:, user:, brand: @brand, latitude: -33.92, longitude: 18.42,
          accuracy_meters: 20, source: "device", captured_at: 2.days.ago
        )
        preference = profile.profile_preference
        preference.update!(interested_in: [ "man" ], min_age: 31, max_age: 41)
        replace_option(profile, "wants_children", "no")

        readiness([ source_row ], publication_policy: :publish_visible_onboarded)
        Profiles::Publication.deactivate!(user:, brand: @brand)
        before = snapshot(profile.reload)

        second = readiness([ source_row ], publication_policy: :publish_visible_onboarded)

        assert_equal before, snapshot(profile.reload)
        assert_equal location.id, ProfileLocation.kept.find_by!(profile:).id
        assert_equal 1, second.reconciliation.count(:intentionally_hidden)
        assert_includes Migration::ProfileReadiness.find_by!(profile:).reason_codes, "native_visibility_preserved"

        identity_rerun = IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: [ source_row ]))
        assert_equal 1, identity_rerun.reconciliation.count(:already_imported)
      end

      test "same-gender preferences are ordinary and remain eligible" do
        rows = [
          row(id: 1, full_name: "Ada Nwosu", gender: 1, looking_for: 1),
          row(id: 2, full_name: "Bisi Adeyemi", gender: 1, looking_for: 1,
            email: "bisi@example.test", date_of_birth: 29.years.ago.to_date)
        ]
        import_identity_and_preferences(rows)
        rows.each { |source_row| attach_ready_photo(profile_for(source_row.fetch(:id))) }
        readiness(rows, publication_policy: :publish_visible_onboarded)

        viewer = profile_for(1)
        candidate = profile_for(2)
        scope = Matching::EligibilityScope.call(
          brand: @brand, viewer:,
          policy: D8n::Platform::Brands::Date9ja::ELIGIBILITY_POLICY
        )
        assert_includes scope, candidate
        assert_equal [ "woman" ], viewer.profile_preference.interested_in
        assert_equal [ "woman" ], candidate.profile_preference.interested_in
      end

      test "classify-only is the fail-closed default while D-8 remains open" do
        source_row = row(id: 1)
        import_identity_and_preferences([ source_row ])
        attach_ready_photo(profile_for(1))

        result = readiness([ source_row ])

        assert_equal 1, result.reconciliation.count(:ready)
        assert profile_for(1).reload.draft?
        assert profile_for(1).hidden?
        assert_nil Migration::ProfileReadiness.find_by!(profile: profile_for(1)).publication_applied_at
      end

      test "a never-onboarded source member is still published — Date9ja shows them in discovery" do
        source_row = row(id: 1, onboarding_completed_at: nil)
        import_identity_and_preferences([ source_row ])

        result = readiness([ source_row ], publication_policy: :publish_visible_onboarded)

        assert_equal 1, result.reconciliation.count(:ready)
        profile = profile_for(1).reload
        assert profile.active?
        assert profile.visible?
      end

      test "a discovery-restricted source member is imported but never published" do
        source_row = row(id: 1, discovery_restricted_at: Time.current)
        import_identity_and_preferences([ source_row ])

        result = readiness([ source_row ], publication_policy: :publish_visible_onboarded)

        assert_equal 1, result.reconciliation.count(:intentionally_hidden)
        profile = profile_for(1).reload
        assert profile.draft?
        assert profile.hidden?
        assert_includes Migration::ProfileReadiness.find_by!(profile:).reason_codes, "source_discovery_restricted"
      end

      test "a source member discovery-restricted after an earlier publish is withdrawn" do
        source_row = row(id: 1)
        import_identity_and_preferences([ source_row ])
        readiness([ source_row ], publication_policy: :publish_visible_onboarded)
        assert profile_for(1).reload.visible?

        restricted = source_row.merge(discovery_restricted_at: Time.current)
        readiness([ restricted ], publication_policy: :publish_visible_onboarded)

        profile = profile_for(1).reload
        assert profile.draft?
        assert profile.hidden?
      end

      test "rerunning readiness is idempotent and creates one current evidence row" do
        source_row = row(id: 1)
        import_identity_and_preferences([ source_row ])
        attach_ready_photo(profile_for(1))

        readiness([ source_row ])
        first = Migration::ProfileReadiness.find_by!(profile: profile_for(1))
        counts = [ User.count, Profile.count, ProfilePreference.count, ProfileLocation.count,
          ProfileOptionSelection.count, Migration::ProfileReadiness.count ]

        result = readiness([ source_row ])

        assert_equal counts, [ User.count, Profile.count, ProfilePreference.count, ProfileLocation.count,
          ProfileOptionSelection.count, Migration::ProfileReadiness.count ]
        assert_equal first.id, Migration::ProfileReadiness.find_by!(profile: profile_for(1)).id
        assert_equal 1, result.reconciliation.count(:ready)
        assert result.reconciliation.balanced?
      end

      test "a rerun does not refill migration-owned values a member later clears" do
        source_row = row(id: 1)
        import_identity_and_preferences([ source_row ])
        profile = profile_for(1)
        attach_ready_photo(profile)
        readiness([ source_row ])
        evidence = Migration::ProfileReadiness.find_by!(profile:)
        # No "location": Date9ja declares no place-selection capability, so
        # readiness never creates a ProfileLocation.
        assert_equal %w[city country_code first_name last_name], evidence.applied_fields

        profile.user.reload.update!(first_name: nil, last_name: nil)
        profile.reload.update!(country_code: nil)

        result = readiness([ source_row ])

        assert_nil profile.user.reload.first_name
        assert_nil profile.user.last_name
        assert_nil profile.reload.country_code
        assert_not ProfileLocation.kept.exists?(profile:)
        assert_equal 1, result.reconciliation.count(:remediation_required)
        reasons = Migration::ProfileReadiness.find_by!(profile:).reason_codes
        # first_name is the one identity gate that remains for a migrated member;
        # a cleared country is preserved-as-cleared and is not a gate.
        assert_includes reasons, "name_confirmation_required"
        assert_not_includes reasons, "location_confirmation_required"
      end

      test "a new (non-migrated) Date9ja member keeps the full cultural completion contract" do
        # Same shape as a migrated member, but with no LegacyReference binding.
        user = User.create!(first_name: "Chidi", last_name: "Eze")
        membership = BrandMembership.create!(user:, brand: @brand)
        profile = Profile.create!(
          user:, brand: @brand, brand_membership: membership, display_name: "Fresh",
          birthdate: 30.years.ago.to_date, gender: "man", country_code: "NG",
          city: "Lagos", bio: "A genuine biography"
        )
        ProfilePreference.create!(profile:, user:, brand: @brand, interested_in: [ "woman" ])
        attach_ready_photo(profile)

        missing = Profiles::Completion.call(profile:).missing.map(&:to_s)

        assert_not Migration::ReferenceMap.migrated?(profile)
        assert_includes missing, "is_nigerian"
        %w[religion family_involvement faith_practice money_providing settlement children conflict].each do |group|
          assert_includes missing, "options.#{group}"
        end
      end

      test "a migrated member published under the migration contract is not later unpublished for a cultural gap" do
        source_row = row(id: 1)
        import_identity_and_preferences([ source_row ])
        attach_ready_photo(profile_for(1))
        readiness([ source_row ], publication_policy: :publish_visible_onboarded)

        profile = profile_for(1).reload
        assert profile.active?
        assert profile.visible?

        Profiles::Publication.unpublish_if_incomplete!(profile: profile.reload)

        assert profile.reload.active?, "a migrated member must stay published through the runtime completion check"
        assert profile.visible?
      end

      test "migration_completion can only relax a requirement, never add one" do
        assert_raises(ActiveRecord::RecordInvalid) do
          @brand.update!(profile_requirements: @brand.profile_requirements.deep_dup.merge(
            "migration_completion" => { "profile_fields" => %w[display_name birthdate gender not_a_real_gate] }
          ))
        end
      end

      test "stale persisted requirements are rejected before any member is changed" do
        @brand.update!(profile_requirements: {
          profile_fields: [], preference_fields: [], collections: [], option_groups: []
        })
        source_row = row(id: 1)

        assert_raises(ProfileReadinessImport::StaleBrandContract) { readiness([ source_row ]) }
        assert_equal 0, Migration::ProfileReadiness.count
      end

      test "an eligible member with no identity import is accounted as a failed import" do
        source_row = row(id: 1)

        result = readiness([ source_row ])

        assert_equal 1, result.reconciliation.count(:failed)
        assert_equal 1, result.reconciliation.reason_count("profile_not_imported")
        assert result.reconciliation.balanced?
        evidence = Migration::ProfileReadiness.find_by!(
          source_system: "date9ja", source_entity: "user", source_id: "1"
        )
        assert evidence.disposition_failed?
        assert_equal [ "profile_not_imported" ], evidence.reason_codes
      end

      private

      def row(id:, **overrides)
        {
          id:, public_id: "pub-#{id}", email: "member#{id}@example.test", phone: nil,
          encrypted_password: BCrypt::Password.create("migration-test", cost: BCrypt::Engine::MIN_COST).to_s,
          confirmed_at: Time.utc(2024, 1, 1), phone_verified_at: nil, created_at: Time.utc(2023, 1, 1),
          deleted_at: nil, suspended_at: nil, banned_at: nil, profile_hidden: false,
          onboarding_completed_at: Time.utc(2024, 2, 1), date_of_birth: 30.years.ago.to_date,
          gender: 0, full_name: "Tunde Okafor", display_name: "Member #{id}", city: "Lagos",
          country_of_residence: " Nigeria ", about_me: "A real biography", ideal_partner_description: "Kind",
          looking_for: 1, preferred_age_min: 25, preferred_age_max: 40,
          preferred_distance_km: nil, relationship_intention: 0, wants_children: 0, children_count: 0
        }.merge(overrides)
      end

      def import_identity_and_preferences(rows)
        source = -> { Snapshot::UserSource.new(rows:) }
        IdentityImport.call(brand: @brand, source: source.call)
        ProfilePreferenceImport.call(brand: @brand, source: source.call)
      end

      def readiness(rows, publication_policy: :classify_only)
        ProfileReadinessImport.call(
          brand: @brand, source: Snapshot::UserSource.new(rows:), publication_policy:
        )
      end

      def profile_for(id)
        Migration::ReferenceMap.resolved(
          source_system: "date9ja", source_entity: "profile", source_id: id.to_s
        )
      end

      def attach_ready_photo(profile)
        photo = ProfilePhoto.new(profile:, user: profile.user, brand: @brand, visibility: :visible)
        photo.image.attach(
          io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
          filename: "profile.png", content_type: "image/png"
        )
        photo.save!
        photo.display_image.attach(
          io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
          filename: "display.jpg", content_type: "image/jpeg"
        )
        photo.update!(processing_state: :ready)
      end

      def replace_option(profile, group_key, option_code)
        group = ProfileOptionGroup.kept.find_by!(brand: @brand, key: group_key)
        selection = ProfileOptionSelection.kept.find_by!(profile:, profile_option_group: group)
        selection.update!(profile_option: group.profile_options.kept.find_by!(code: option_code))
      end

      def snapshot(profile)
        {
          names: [ profile.user.first_name, profile.user.last_name ],
          country_city: [ profile.country_code, profile.city ],
          location: profile.profile_locations.kept.pick(:id, :latitude, :longitude, :captured_at),
          preference: profile.profile_preference.attributes.slice("interested_in", "min_age", "max_age"),
          wants_children: profile.profile_option_selections.kept.joins(:profile_option_group, :profile_option)
            .find_by!(profile_option_groups: { key: "wants_children" }).profile_option.code,
          publication: [ profile.status, profile.visibility ]
        }
      end
    end
  end
end
