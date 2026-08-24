require "test_helper"

module Matching
  class ExclusionsScopeTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      @viewer = create_profile(brand: @brand)
    end

    test "universally excludes outgoing Likes Passes and active Matches without querying Hooks" do
      matched_as_b = create_profile(brand: @brand)
      viewer = create_profile(brand: @brand)
      liked = create_profile(brand: @brand)
      passed = create_profile(brand: @brand)
      matched_as_a = create_profile(brand: @brand)
      available = create_profile(brand: @brand)
      Like.create!(brand: @brand, liker_profile: viewer, liked_profile: liked)
      ProfilePass.create!(brand: @brand, passer_profile: viewer, passed_profile: passed)
      create_match(viewer, matched_as_a)
      create_match(matched_as_b, viewer)
      candidates = @brand.profiles.where(id: [ liked, passed, matched_as_a, matched_as_b, available ])

      scope = ExclusionsScope.call(scope: candidates, viewer:)

      assert_equal [ available.id ], scope.pluck(:id)
      assert_no_match(/\b(?:FROM|JOIN)\s+"?hooks"?/i, scope.to_sql)
    end

    test "applies live Hook exclusion only when the surface contributes it" do
      outgoing = create_profile(brand: @brand)
      incoming = create_profile(brand: @brand)
      expired = create_profile(brand: @brand)
      declined = create_profile(brand: @brand)
      available = create_profile(brand: @brand)
      Hook.create!(brand: @brand, sender_profile: @viewer, recipient_profile: outgoing, message: "outgoing")
      Hook.create!(brand: @brand, sender_profile: incoming, recipient_profile: @viewer, message: "incoming")
      Hook.create!(
        brand: @brand, sender_profile: @viewer, recipient_profile: expired,
        message: "expired", expires_at: 1.minute.ago
      )
      Hook.create!(
        brand: @brand, sender_profile: @viewer, recipient_profile: declined,
        message: "declined", status: :declined
      )

      base_ids = ExclusionsScope.call(scope: candidate_scope, viewer: @viewer).pluck(:id)
      composed = ExclusionsScope.call(
        scope: candidate_scope, viewer: @viewer, contributors: [ Hooks::DiscoveryExclusion ]
      )

      assert_includes base_ids, outgoing.id
      assert_includes base_ids, incoming.id
      assert_equal [ expired.id, declined.id, available.id ].sort, composed.pluck(:id).sort
      assert_match(/\bFROM\s+"hooks"/i, composed.to_sql)
    end

    test "DateZA Find executes no Hook table query when Hooks are not configured" do
      dateza = Brand.create!(slug: "dateza", name: "DateZA")
      viewer = create_profile(brand: dateza, gender: "woman", interested_in: [ "man" ])
      create_profile(brand: dateza, gender: "man", interested_in: [ "woman" ])
      statements = []
      collector = ->(_name, _start, _finish, _id, payload) { statements << payload.fetch(:sql) }

      ActiveSupport::Notifications.subscribed(collector, "sql.active_record") do
        Find::Search.call(user: viewer.user, brand: dateza)
      end

      hook_queries = statements.grep(/\b(?:FROM|JOIN)\s+"?hooks"?/i)
      assert_empty hook_queries
    end

    private

    def candidate_scope
      @brand.profiles.where.not(id: @viewer.id)
    end

    def create_match(first, second)
      profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
      Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
    end

    def create_profile(brand:, gender: "woman", interested_in: [ "woman" ])
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, status: :active, visibility: :visible,
        birthdate: 30.years.ago.to_date, gender:
      )
      ProfilePreference.create!(
        brand:, user:, profile:, interested_in:, min_age: 18, max_age: 60
      )
      profile
    end
  end
end
