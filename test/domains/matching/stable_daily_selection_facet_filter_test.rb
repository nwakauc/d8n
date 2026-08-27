require "test_helper"

module Matching
  # T6: proves Matching::StableDailySelection actually APPLIES a parsed
  # FacetFilter (not just validates it) — DateZA's real "discovery.curated_daily"
  # surface has no facets configured today, so this constructs a synthetic
  # surface with an activity facet to exercise the mechanism directly.
  class StableDailySelectionFacetFilterTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "dateza", name: "DateZA")
      Profiles::DatezaProfileCatalog.install!(brand: @brand)
      BrandDomain.create!(brand: @brand, host: "dateza-facet.test")
      @viewer = create_profile(brand: @brand, gender: "woman", age: 30, interested_in: [ "man" ])
      @surface = D8n::Platform::DiscoverySurface.new(
        key: "discovery.curated_daily",
        delivery_type: :daily_batch,
        strategy: Matching::Strategies::DatezaV1,
        eligibility_policy: D8n::Platform::Brands::Dateza::ELIGIBILITY_POLICY,
        facets: [ { type: :activity, parameter: :online } ],
        allocation: D8n::Platform::StableDailyAllocationPolicy.new(
          key: "facet_test_v1", daily_limit: 10, time_zone: "Africa/Johannesburg"
        ),
        error_code: :matching_not_configured
      )
    end

    test "an activity facet actually excludes offline candidates from both allocation and delivery" do
      online = create_profile(brand: @brand, gender: "man", age: 30, interested_in: [ "woman" ])
      Session.issue!(brand: @brand, user: online.user)
      offline = create_profile(brand: @brand, gender: "man", age: 30, interested_in: [ "woman" ])

      filter = FacetFilter.parse(brand: @brand, definitions: @surface.facets, params: { "online" => "true" })
      result = StableDailySelection.call(user: @viewer.user, brand: @brand, surface: @surface, filter:)

      assert_equal [ online.id ], result.profiles.map(&:id)
      assert_not_includes result.profiles.map(&:id), offline.id
      assert_equal [ online.id ], DiscoveryAllocationCandidate.where(brand: @brand).pluck(:candidate_profile_id),
        "the offline candidate must never even be written into the allocation"
    end

    test "with no filter value supplied, the facet is a no-op and both candidates are allocated" do
      online = create_profile(brand: @brand, gender: "man", age: 30, interested_in: [ "woman" ])
      Session.issue!(brand: @brand, user: online.user)
      offline = create_profile(brand: @brand, gender: "man", age: 30, interested_in: [ "woman" ])

      filter = FacetFilter.parse(brand: @brand, definitions: @surface.facets, params: {})
      result = StableDailySelection.call(user: @viewer.user, brand: @brand, surface: @surface, filter:)

      assert_equal [ online.id, offline.id ].to_set, result.profiles.map(&:id).to_set
    end

    private

    def create_profile(brand:, gender:, age:, interested_in:)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, gender:,
        birthdate: age.years.ago.to_date, status: :active, visibility: :visible
      )
      ProfilePreference.create!(
        brand:, user:, profile:, min_age: 18, max_age: 80, interested_in:
      )
      profile
    end
  end
end
