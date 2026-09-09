# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Import
    class ProfilePreferenceImportTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        Profiles::Date9jaProfileCatalog.install!(brand: @brand)
      end

      # Source rows carry the REAL legacy shape: integer enum codes, not words.
      def row(id:, **overrides)
        {
          "id" => id,
          "public_id" => "pub-#{id}",
          "email" => "member#{id}@example.com",
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
          "gender" => 1,
          "display_name" => "Member #{id}",
          "city" => "Lagos",
          "country_of_residence" => "NG",
          "about_me" => "hello there",
          "ideal_partner_description" => "someone kind",
          "looking_for" => 0,
          "preferred_age_min" => 25,
          "preferred_age_max" => 40,
          "preferred_distance_km" => nil,
          "relationship_intention" => 0,
          "wants_children" => 0,
          "children_count" => 0
        }.merge(overrides.transform_keys(&:to_s))
      end

      def synthetic_digest = BCrypt::Password.create("correct horse battery staple", cost: 4).to_s

      # The preference importer consumes what the identity importer produced, so
      # every test runs the real chain rather than fabricating a Profile.
      def import(rows)
        source = Snapshot::UserSource.new(rows: rows)
        IdentityImport.call(brand: @brand, source: source)
        ProfilePreferenceImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: rows))
      end

      def import_identity_only(source)
        IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: [ source ]))
      end

      def preference_for(source_id)
        Migration::ReferenceMap.resolved(
          source_system: "date9ja", source_entity: "profile_preference", source_id: source_id.to_s
        )
      end

      def profile_for(source_id)
        Migration::ReferenceMap.resolved(
          source_system: "date9ja", source_entity: "profile", source_id: source_id.to_s
        )
      end

      def selections_for(source_id)
        ProfileOptionSelection.kept.where(profile: profile_for(source_id))
          .includes(:profile_option_group, :profile_option)
          .to_h { |s| [ s.profile_option_group.key, s.profile_option.code ] }
      end

      # --- the core outcome --------------------------------------------------

      test "creates a bound ProfilePreference carrying the member's stated values" do
        result = import([ row(id: 1) ])

        preference = preference_for(1)
        assert preference, "a ProfilePreference must be bound through ReferenceMap"
        assert_equal [ "man" ], preference.interested_in
        assert_equal 25, preference.min_age
        assert_equal 40, preference.max_age
        assert_equal @brand.id, preference.brand_id
        assert_equal 1, result.reconciliation.count(:preferences_created)
        assert result.reconciliation.balanced?
      end

      test "decodes the legacy gender code the identity slice left in place" do
        # Simulate the state the VERIFIED identity rehearsal actually produced.
        rows = [ row(id: 1, gender: 0) ]
        IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: rows))
        profile_for(1).update_column(:gender, "0")

        ProfilePreferenceImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: rows))

        assert_equal "man", profile_for(1).reload.gender
      end

      test "the migrated member now satisfies every matching participation rule" do
        import([ row(id: 1, gender: 1, looking_for: 0) ])

        profile = profile_for(1)
        preference = preference_for(1)

        # Matching::ProfileParticipant's three requirements, none of which any
        # migrated member met before this slice existed.
        assert preference.min_age.present?
        assert preference.max_age.present?
        assert preference.interested_in.any?
        # EligibilityScope compares these two verbatim, in both directions.
        assert_equal "woman", profile.gender
        assert_equal [ "man" ], preference.interested_in
      end

      # The end-to-end proof: two migrated members, run through the REAL
      # discovery scope, actually see each other. Publication is still D-8's
      # call, so the test publishes them explicitly to isolate the question this
      # slice is responsible for -- whether the migrated VALUES are compatible.
      test "two migrated members find each other through the real discovery scope" do
        import([
          row(id: 1, gender: 1, looking_for: 0, preferred_age_min: 25, preferred_age_max: 40),
          row(id: 2, gender: 0, looking_for: 1, preferred_age_min: 25, preferred_age_max: 40,
              email: "b@example.com")
        ])
        publish!(profile_for(1))
        publish!(profile_for(2))

        assert_equal [ profile_for(2).id ], discoverable_by(profile_for(1)).pluck(:id)
        assert_equal [ profile_for(1).id ], discoverable_by(profile_for(2)).pluck(:id)
      end

      test "a migrated same-gender pair is discoverable on exactly the same terms" do
        import([
          row(id: 1, gender: 0, looking_for: 0, preferred_age_min: 25, preferred_age_max: 40),
          row(id: 2, gender: 0, looking_for: 0, preferred_age_min: 25, preferred_age_max: 40,
              email: "b@example.com")
        ])
        publish!(profile_for(1))
        publish!(profile_for(2))

        assert_equal [ profile_for(2).id ], discoverable_by(profile_for(1)).pluck(:id)
        assert_equal [ profile_for(1).id ], discoverable_by(profile_for(2)).pluck(:id)
      end

      test "a member seeking their own gender migrates exactly like anyone else" do
        # Some Date9ja members are gay. Same-gender interest is a value to carry
        # across faithfully, never a defect to flag, quarantine, or re-ask.
        result = import([ row(id: 1, gender: 0, looking_for: 0) ])

        assert_equal "man", profile_for(1).gender
        assert_equal [ "man" ], preference_for(1).interested_in
        assert_equal 1, result.reconciliation.count(:imported)
        assert_equal 0, result.reconciliation.count(:failed)
        assert_equal 0, result.reconciliation.note_count("interested_in_unmapped")
      end

      test "writes one option selection per mappable group" do
        import([ row(id: 1, relationship_intention: 0, children_count: 2, wants_children: 1) ])

        assert_equal({ "relationship_intent" => "marriage", "has_children" => "yes",
                       "wants_children" => "no", "children_count" => "two" }, selections_for(1))
      end

      test "rolls back the member when an approved option group is missing" do
        source = row(id: 1)
        import_identity_only(source)

        importer = ProfilePreferenceImport.new(brand: @brand,
          source: Snapshot::UserSource.new(rows: [ source ]))
        def importer.option_group(_key) = nil
        result = importer.call
        assert_equal 1, result.reconciliation.count(:failed)
        assert_equal 1, result.reconciliation.reason_count("approved_option_group_missing")
        assert result.reconciliation.balanced?

        assert_nil preference_for(1)
        assert_empty ProfileOptionSelection.where(profile: profile_for(1))
      end

      test "rolls back and succeeds on rerun after an approved option is restored" do
        source = row(id: 1)
        import_identity_only(source)
        group = ProfileOptionGroup.kept.find_by!(brand: @brand, key: "relationship_intent")
        option = group.profile_options.kept.find_by!(code: "marriage")
        option.update!(status: :retired)

        failed = ProfilePreferenceImport.call(brand: @brand,
          source: Snapshot::UserSource.new(rows: [ source ]))
        assert_equal 1, failed.reconciliation.count(:failed)
        assert_nil preference_for(1)
        assert_empty ProfileOptionSelection.where(profile: profile_for(1))

        option.update!(status: :active)
        succeeded = ProfilePreferenceImport.call(brand: @brand,
          source: Snapshot::UserSource.new(rows: [ source ]))
        assert_equal 1, succeeded.reconciliation.count(:imported)
        assert_equal 0, succeeded.reconciliation.count(:failed)
        assert preference_for(1)
        # relationship_intent, has_children, wants_children, children_count.
        assert_equal 4, ProfileOptionSelection.where(profile: profile_for(1)).count
      end

      test "rolls back the member when option-selection persistence is invalid" do
        source = row(id: 1)
        import_identity_only(source)
        original_create = ProfileOptionSelection.method(:create!)
        invalid = ActiveRecord::RecordInvalid.new(ProfileOptionSelection.new)
        ProfileOptionSelection.define_singleton_method(:create!) { |*| raise invalid }
        begin
          result = ProfilePreferenceImport.call(brand: @brand,
            source: Snapshot::UserSource.new(rows: [ source ]))
          assert_equal 1, result.reconciliation.count(:failed)
          assert_equal 1, result.reconciliation.reason_count("option_selection_invalid")
          assert result.reconciliation.balanced?
        ensure
          ProfileOptionSelection.define_singleton_method(:create!, original_create)
        end

        assert_nil preference_for(1)
        assert_empty ProfileOptionSelection.where(profile: profile_for(1))
      end

      # --- never inventing anything -----------------------------------------

      test "never writes max_distance_km, which has no source value at all" do
        import([ row(id: 1, preferred_distance_km: nil) ])

        assert_nil preference_for(1).max_distance_km
      end

      test "an out-of-domain option code is left unselected and recorded, not guessed" do
        # relationship_intention is a 0..5 enum; 99 is not a real value.
        result = import([ row(id: 1, relationship_intention: 99) ])

        refute_includes selections_for(1).keys, "relationship_intent"
        assert_equal 1, result.reconciliation.note_count("relationship_intent_unmapped")
        assert_equal 1, result.reconciliation.count(:imported), "an unmapped code is not a failure"
      end

      test "every legacy preference/lifestyle enum is preserved as an option selection" do
        result = import([ row(id: 1,
          relationship_intention: 1, wants_children: 2, children_count: 3,
          family_involvement_preference: 1, commitment_timeline: 4,
          marital_status: 1, education: 1) ])

        sel = selections_for(1)
        assert_equal "courtship", sel["relationship_intent"]
        assert_equal "open", sel["wants_children"]
        assert_equal "yes", sel["has_children"]
        assert_equal "three_or_more", sel["children_count"]
        assert_equal "medium", sel["family_involvement_level"]
        assert_equal "not_sure", sel["commitment_timeline"]
        assert_equal "divorced", sel["marital_status"]
        assert_equal "diploma", sel["education_level"]
        assert_equal 1, result.reconciliation.count(:imported)
      end

      test "leaves an unanswered field unset and distinguishes it from unmapped" do
        result = import([ row(id: 1, relationship_intention: nil, wants_children: nil) ])

        assert_equal 1, result.reconciliation.note_count("relationship_intent_absent")
        assert_equal 0, result.reconciliation.note_count("relationship_intent_unmapped")
        assert_equal 1, result.reconciliation.note_count("wants_children_absent")
      end

      test "reports a half-answered age range as partial, not as invalid data" do
        # The real corpus contains exactly one of these. Calling it "invalid"
        # would contradict the census, which proved 0 out-of-range and 0 inverted.
        result = import([ row(id: 1, preferred_age_min: 25, preferred_age_max: nil) ])

        assert_nil preference_for(1).min_age
        assert_equal 1, result.reconciliation.note_count("age_range_partial")
        assert_equal 0, result.reconciliation.note_count("age_range_invalid")
        assert_equal 0, result.reconciliation.note_count("age_range_absent")
      end

      test "drops an invalid or inverted age range rather than clamping it" do
        result = import([
          row(id: 1, preferred_age_min: 40, preferred_age_max: 25),
          row(id: 2, preferred_age_min: 12, preferred_age_max: 30, email: "b@example.com")
        ])

        assert_nil preference_for(1).min_age
        assert_nil preference_for(2).min_age
        assert_equal 2, result.reconciliation.note_count("age_range_invalid")
      end

      test "records that meeting_pace and max_distance_km have no legacy source" do
        result = import([ row(id: 1) ])

        assert_equal 1, result.reconciliation.note_count("meeting_pace_no_source")
        assert_equal 1, result.reconciliation.note_count("max_distance_km_no_source")
        refute_includes selections_for(1).keys, "meeting_pace"
      end

      # --- idempotency -------------------------------------------------------

      test "a second run creates nothing new" do
        rows = [ row(id: 1), row(id: 2, email: "b@example.com") ]
        import(rows)

        counts = -> { [ ProfilePreference.count, ProfileOptionSelection.count, LegacyReference.count ] }
        before = counts.call
        result = ProfilePreferenceImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: rows))

        assert_equal before, counts.call
        assert_equal 2, result.reconciliation.count(:already_imported)
        assert_equal 0, result.reconciliation.count(:imported)
        assert result.reconciliation.balanced?
      end

      test "a re-run never overwrites an answer the member changed in D8N" do
        rows = [ row(id: 1, looking_for: 0) ]
        import(rows)
        preference_for(1).update!(interested_in: [ "woman" ], min_age: 30, max_age: 35)

        ProfilePreferenceImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: rows))

        preference = preference_for(1).reload
        assert_equal [ "woman" ], preference.interested_in, "the member's own answer stands"
        assert_equal 30, preference.min_age
      end

      test "a re-run fills a gap a previous run had to leave open" do
        rows = [ row(id: 1, looking_for: nil) ]
        import(rows)
        assert_empty preference_for(1).interested_in

        answered = [ row(id: 1, looking_for: 1) ]
        ProfilePreferenceImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: answered))

        assert_equal [ "woman" ], preference_for(1).reload.interested_in
      end

      test "a re-run does not replace a selection the member changed" do
        rows = [ row(id: 1, wants_children: 0) ]
        import(rows)
        assert_equal "yes", selections_for(1).fetch("wants_children")

        group = ProfileOptionGroup.kept.find_by(brand: @brand, key: "wants_children")
        ProfileOptionSelection.kept.where(profile: profile_for(1), profile_option_group: group)
          .update_all(profile_option_id: group.profile_options.kept.find_by(code: "no").id)

        ProfilePreferenceImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: rows))

        assert_equal "no", selections_for(1).fetch("wants_children")
      end

      # --- eligibility and failure isolation ---------------------------------

      test "skips the rows the identity importer skipped, for the same reason" do
        result = import([
          row(id: 1, deleted_at: Time.utc(2024, 5, 1)),
          row(id: 2, banned_at: Time.utc(2024, 5, 1), email: "b@example.com")
        ])

        assert_equal 2, result.reconciliation.count(:skipped)
        assert_equal 1, result.reconciliation.reason_count("source_soft_deleted")
        assert_equal 1, result.reconciliation.reason_count("source_banned")
        assert_equal 0, ProfilePreference.count
        assert result.reconciliation.balanced?
      end

      test "skips a member the identity importer never imported" do
        rows = [ row(id: 1) ]
        result = ProfilePreferenceImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: rows))

        assert_equal 1, result.reconciliation.reason_count("profile_not_imported")
        assert_equal 0, ProfilePreference.count
      end

      test "every considered row lands in exactly one disposition" do
        result = import([
          row(id: 1),
          row(id: 2, deleted_at: Time.utc(2024, 5, 1), email: "b@example.com"),
          row(id: 3, relationship_intention: 5, email: "c@example.com")
        ])

        recon = result.reconciliation.to_h
        assert_equal 3, recon["source_users_considered"]
        assert_equal 3, recon["dispositions"].values.sum
        assert recon["balanced"]
      end

      test "the reconciliation carries counts and reason codes only, never member data" do
        result = import([ row(id: 1, display_name: "Adaeze Okafor", email: "adaeze@example.com") ])
        serialized = result.reconciliation.to_h.to_json

        %w[ Adaeze Okafor adaeze@example.com Lagos ].each do |needle|
          refute_includes serialized, needle
        end
      end

      def publish!(profile)
        profile.update!(status: :active, visibility: :visible)
      end

      def discoverable_by(viewer)
        Matching::EligibilityScope.call(
          brand: @brand, viewer: viewer,
          policy: D8n::Platform::Brands::Date9ja::ELIGIBILITY_POLICY
        )
      end

      test "refuses to run against a brand that is not date9ja" do
        other = Brand.create!(slug: "dateza", name: "DateZA")

        assert_raises(ProfilePreferenceImport::WrongBrand) do
          ProfilePreferenceImport.call(brand: other, source: Snapshot::UserSource.new(rows: []))
        end
      end
    end
  end
end
