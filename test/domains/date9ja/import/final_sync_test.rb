require "test_helper"

module Date9ja
  module Import
    class FinalSyncTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja", auth_methods: %w[email_password phone_password])
        Profiles::Date9jaProfileCatalog.install!(brand: @brand)
        @other = Brand.create!(slug: "hookus", name: "HookUs")
        @other_user = User.create!
        @other_membership = BrandMembership.create!(user: @other_user, brand: @other)
        @other_profile = Profile.create!(user: @other_user, brand: @other, brand_membership: @other_membership)
        @digest = BCrypt::Password.create("synthetic-password", cost: 4).to_s
        @source = (1..4).map { |id| source_row(id) }
        IdentityImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: @source))
        ProfilePreferenceImport.call(brand: @brand, source: Snapshot::UserSource.new(rows: @source))
        @baseline = SyncBundle.export(brand: @brand)
      end

      def source_row(id)
        { id:, email: "synthetic#{id}@example.com", encrypted_password: @digest,
          display_name: "Synthetic #{id}", gender: 1, date_of_birth: "1990-01-01",
          country_of_residence: "NG", looking_for: 0, preferred_age_min: 25, preferred_age_max: 40,
          relationship_intention: 0, wants_children: 0, children_count: 0, confirmed_at: "2024-01-01", created_at: "2023-01-01" }
      end

      def resolved(entity, id)
        Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: entity, source_id: id.to_s)
      end

      def attrs(bundle, entity, id)
        bundle.fetch("rows").find { |row| row.fetch("key") == [ entity, id.to_s ] }.fetch("attributes")
      end

      def ref(entity, id) = { "$ref" => [ entity, id.to_s ] }

      def add(bundle, entity, id, type, attributes)
        bundle["rows"] << { "key" => [ entity, id.to_s ], "type" => type, "attributes" => attributes }
      end

      def counts
        [ User, IdentityIdentifier, Credential, BrandMembership, Profile, ProfilePreference,
          Like, Match, Conversation, Message, LegacyReference ].map(&:count)
      end

      test "baseline to final synchronization preserves native activity and reruns without creations" do
        # Native activity after snapshot A, and an unrelated brand with IDs that
        # precede the imported cohort. Source IDs are never destination IDs.
        a, b = resolved("profile", 1), resolved("profile", 2)
        a.update!(bio: "Native biography")
        preference = resolved("profile_preference", 1)
        preference.update!(preferred_country_codes: [ "GB" ])
        match = Match.create!(brand: @brand, profile_a: [ a, b ].min_by(&:id), profile_b: [ a, b ].max_by(&:id))
        conversation = Conversation.create!(brand: @brand, match:)
        native = Message.create!(brand: @brand, conversation:, sender_profile: a, body: "Native message")
        other_before = [ @other_user, @other_membership, @other_profile ].map(&:attributes)
        desired = @baseline.deep_dup
        attrs(desired, "profile", 1)["city"] = "Abuja"
        attrs(desired, "profile_preference", 1)["min_age"] = 27
        options = desired["options"].find { |entry| entry["key"] == [ "profile", "1" ] }
        options["values"].map! { |group, code| [ group, group == "relationship_intent" ? "long_term_relationship" : code ] }
        attrs(desired, "profile", 2)["visibility"] = "hidden"
        attrs(desired, "membership", 3)["status"] = "suspended"
        attrs(desired, "profile", 3)["status"] = "suspended"
        desired["passwords"].first["attributes"]["password_hash"] = BCrypt::Password.create("new-source-password", cost: 4).to_s
        add(desired, "user", 5, "User", {})
        add(desired, "identity_email", 5, "IdentityIdentifier", { "user_id" => ref("user", 5), "brand_id" => { "$brand" => true }, "kind" => "email", "normalized_value" => "new-synthetic@example.com" })
        add(desired, "password_credential", 5, "Credential", { "user_id" => ref("user", 5), "identity_identifier_id" => ref("identity_email", 5), "kind" => "password", "status" => "active" })
        desired["passwords"] << { "key" => [ "password_credential", "5" ],
          "attributes" => { "password_hash" => @digest, "credential_kind" => "password", "password_changed_at" => "2026-09-18T07:00:00Z" } }
        add(desired, "membership", 5, "BrandMembership", { "user_id" => ref("user", 5), "brand_id" => { "$brand" => true }, "status" => "active" })
        add(desired, "profile", 5, "Profile", { "user_id" => ref("user", 5), "brand_id" => { "$brand" => true }, "brand_membership_id" => ref("membership", 5), "display_name" => "New synthetic", "status" => "draft", "visibility" => "hidden" })
        add(desired, "like", 1, "Like", { "brand_id" => { "$brand" => true }, "liker_profile_id" => ref("profile", 1), "liked_profile_id" => ref("profile", 2), "kind" => "like", "deleted_at" => nil })
        # Adopt the exact native match/conversation by their semantic keys, then
        # preserve its native message while adding the final-source message.
        add(desired, "match", 1, "Match", { "brand_id" => { "$brand" => true }, "profile_a_id" => ref("profile", 1), "profile_b_id" => ref("profile", 2), "status" => "active", "deleted_at" => nil })
        add(desired, "conversation", 1, "Conversation", { "brand_id" => { "$brand" => true }, "match_id" => ref("match", 1), "status" => "active", "deleted_at" => nil })
        add(desired, "message", 1, "Message", { "brand_id" => { "$brand" => true }, "conversation_id" => ref("conversation", 1), "sender_profile_id" => ref("profile", 2), "body" => "Final source message" })
        first = FinalSync.call(brand: @brand, baseline: @baseline, desired:, apply: true)
        assert_operator first.fetch("created"), :>, 0
        assert_equal "Native biography", a.reload.bio
        assert_equal "Abuja", a.city
        assert_equal 27, preference.reload.min_age
        assert_equal [ "GB" ], preference.preferred_country_codes
        assert_equal [ "long_term_relationship" ], ProfileOptionSelection.kept.where(profile: a)
          .joins(:profile_option_group, :profile_option).where(profile_option_groups: { key: "relationship_intent" }).pluck("profile_options.code")
        assert_equal "hidden", b.reload.visibility
        assert Identity::PasswordEngine.matches?(credential: resolved("password_credential", 5), password: "synthetic-password")
        assert resolved("membership", 3).suspended?
        assert_equal native.attributes, native.reload.attributes
        assert_equal 2, conversation.messages.count
        assert_equal 2, conversation.conversation_participants.count
        assert_equal other_before, [ @other_user, @other_membership, @other_profile ].map { |record| record.reload.attributes }
        after = counts
        second = FinalSync.call(brand: @brand, baseline: @baseline, desired:, apply: true)
        assert_equal 0, second.fetch("created", 0)
        assert_equal 0, second.fetch("updated", 0)
        assert_equal 0, second.fetch("passwords.updated", 0)
        assert_equal after, counts
        assert_equal native.attributes, native.reload.attributes
        assert_equal other_before, [ @other_user, @other_membership, @other_profile ].map { |record| record.reload.attributes }
      end

      test "unchanged source preserves native recovery, pause, hide and ended match" do
        a, b = resolved("profile", 1), resolved("profile", 2)
        a.update!(visibility: :hidden)
        resolved("membership", 1).update!(status: :deactivated)
        credential = resolved("password_credential", 1)
        credential.credential_password_hash.update!(password_hash: BCrypt::Password.create("native-recovery", cost: 4).to_s)
        match = Match.create!(brand: @brand, profile_a: [ a, b ].min_by(&:id), profile_b: [ a, b ].max_by(&:id), status: :ended)
        before = [ a, resolved("membership", 1), match ].map(&:attributes)
        twice = 2.times.map { FinalSync.call(brand: @brand, baseline: @baseline, desired: @baseline.deep_dup, apply: true) }
        assert twice.all? { |counts| counts.fetch("created", 0).zero? && counts.fetch("updated", 0).zero? }
        assert Identity::PasswordEngine.matches?(credential: credential.reload, password: "native-recovery")
        assert_equal before, [ a, resolved("membership", 1), match ].map { |record| record.reload.attributes }
      end

      test "trust ledger awards remain append only" do
        profile = resolved("profile", 1)
        event = TrustEvent.create!(brand: @brand, user: profile.user, profile:, event_type: "synthetic", points: 1,
          idempotency_key: "synthetic-award", occurred_at: Time.current)
        Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: "trust_event", source_id: "1",
          destination: event, brand: @brand, importer_version: "synthetic")
        baseline = SyncBundle.export(brand: @brand)
        desired = baseline.deep_dup
        attrs(desired, "trust_event", 1)["points"] = 2
        error = assert_raises(FinalSync::Conflict) { FinalSync.call(brand: @brand, baseline:, desired:, apply: true) }
        assert_equal "append_only_ledger_change", error.message
        assert_equal 1, event.reload.points
      end

      test "new media cannot be published without its verified attachment graph" do
        desired = @baseline.deep_dup
        add(desired, "photo", 1, "ProfilePhoto", { "brand_id" => { "$brand" => true },
          "user_id" => ref("user", 1), "profile_id" => ref("profile", 1), "position" => 0,
          "processing_state" => "ready", "visibility" => "visible" })
        before = counts
        error = assert_raises(FinalSync::Conflict) { FinalSync.call(brand: @brand, baseline: @baseline, desired:, apply: true) }
        assert_equal "media_graph_required", error.message
        assert_equal before, counts
      end

      test "dual profile and password changes abort atomically" do
        desired = @baseline.deep_dup
        attrs(desired, "profile", 1)["city"] = "Source city"
        resolved("profile", 1).update!(city: "Native city")
        before = counts
        assert_raises(FinalSync::Conflict) { FinalSync.call(brand: @brand, baseline: @baseline, desired:, apply: true) }
        assert_equal before, counts
        assert_equal "Native city", resolved("profile", 1).city
        desired = @baseline.deep_dup
        desired["passwords"].first["attributes"]["password_hash"] = BCrypt::Password.create("source-password", cost: 4).to_s
        credential = resolved("password_credential", 1)
        credential.credential_password_hash.update!(password_hash: BCrypt::Password.create("native-password", cost: 4).to_s)
        assert_raises(FinalSync::Conflict) { FinalSync.call(brand: @brand, baseline: @baseline, desired:, apply: true) }
        assert Identity::PasswordEngine.matches?(credential:, password: "native-password")
      end

      test "dry run rolls back, numeric copied IDs and unexplained omissions fail closed" do
        desired = @baseline.deep_dup
        attrs(desired, "profile", 1)["city"] = "Preview city"
        FinalSync.call(brand: @brand, baseline: @baseline, desired:)
        assert_nil resolved("profile", 1).city
        attrs(desired, "profile", 1)["user_id"] = @other_user.id
        assert_raises(FinalSync::Conflict) { FinalSync.call(brand: @brand, baseline: @baseline, desired:, apply: true) }
        desired = @baseline.deep_dup
        desired["rows"].reject! { |row| row["key"] == [ "profile", "4" ] }
        assert_raises(FinalSync::Conflict) { FinalSync.call(brand: @brand, baseline: @baseline, desired:, apply: true) }
        assert_nil resolved("profile", 4).deleted_at
      end

      test "attested deletion closes only brand presence and never resurrects on rerun" do
        user = resolved("user", 4)
        other_membership = BrandMembership.create!(brand: @other, user:)
        other_profile = Profile.create!(brand: @other, user:, brand_membership: other_membership)
        unchanged = [ user.attributes, other_membership.attributes, other_profile.attributes ]
        desired = @baseline.deep_dup
        desired["rows"].reject! { |row| row["key"] == [ "profile", "4" ] }
        desired["removals"] << { "key" => [ "profile", "4" ], "reason" => "source_deleted", "at" => Time.current.iso8601(6) }
        FinalSync.call(brand: @brand, baseline: @baseline, desired:, apply: true)
        assert resolved("profile", 4).deleted_at
        assert resolved("membership", 4).left?
        after = counts
        FinalSync.call(brand: @brand, baseline: @baseline, desired:, apply: true)
        assert_equal after, counts
        assert_equal unchanged, [ user, other_membership, other_profile ].map { |record| record.reload.attributes }
      end
    end
  end
end
