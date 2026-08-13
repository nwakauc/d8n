require "test_helper"

module Matching
  class StrategyContractTest < ActiveSupport::TestCase
    setup do
      @date9ja = Brand.create!(slug: "date9ja", name: "Date9ja")
      @viewer = create_profile(
        brand: @date9ja, gender: "woman", age: 30,
        interested_in: [ "man" ], min_age: 25, max_age: 40
      )
    end

    test "keeps the Date9ja contract out of the production registry" do
      assert_raises(StrategyRegistry::UnsupportedBrand) { StrategyRegistry.fetch(brand: @date9ja) }
      assert_equal Strategies::Date9jaContract, StrategyRegistry.contract_for(brand: @date9ja)
      assert_not Strategies::Date9jaContract.production_ready?
      assert Strategies::Hookus.production_ready?
      assert StrategyRegistry::STRATEGIES.values.all?(&:production_ready?)
    end

    test "both strategies implement the discovery contract" do
      required_methods = %i[
        key location_max_age production_ready? rank cursor_payload apply_cursor compatibility
      ]

      [ Strategies::Hookus, Strategies::Date9jaContract ].each do |strategy|
        required_methods.each { |method| assert_respond_to strategy, method }
      end
    end

    test "uses shared eligibility and a separate deterministic cursor contract" do
      candidates = 3.times.map { create_candidate(brand: @date9ja) }
      candidates.each_with_index do |candidate, index|
        candidate.update_columns(created_at: Time.utc(2026, 8, 13, 14, 0, index), updated_at: Time.current)
      end
      other_brand = Brand.create!(slug: "other", name: "Other")
      create_candidate(brand: other_brand)
      strategy = StrategyRegistry.contract_for(brand: @date9ja)
      scope = EligibilityScope.call(
        brand: @date9ja,
        viewer: @viewer,
        location_max_age: strategy.location_max_age
      )
      ranked = strategy.rank(scope:, viewer: @viewer)
      first_page = ranked.limit(2).to_a
      cursor = Cursor.encode(brand: @date9ja, strategy:, profile: first_page.last)
      second_page = Cursor.apply(scope: ranked, value: cursor, brand: @date9ja, strategy:).limit(2).to_a

      assert_equal [ candidates[2].id, candidates[1].id ], first_page.pluck(:id)
      assert_equal [ candidates[0].id ], second_page.pluck(:id)
      assert_equal({ score: 0, confidence: 0.0, reasons: [] }, strategy.compatibility(profile: first_page.first))
    end

    test "binds contract cursors to Date9ja and its strategy key" do
      candidate = create_candidate(brand: @date9ja)
      strategy = StrategyRegistry.contract_for(brand: @date9ja)
      ranked = strategy.rank(scope: @date9ja.profiles.where(id: candidate.id), viewer: @viewer).first
      cursor = Cursor.encode(brand: @date9ja, strategy:, profile: ranked)
      other_brand = Brand.create!(slug: "other", name: "Other")

      assert_raises Cursor::Invalid do
        Cursor.apply(scope: other_brand.profiles, value: cursor, brand: other_brand, strategy:)
      end
    end

    private

    def create_candidate(brand:)
      create_profile(
        brand:, gender: "man", age: 30,
        interested_in: [ "woman" ], min_age: 25, max_age: 40
      )
    end

    def create_profile(brand:, gender:, age:, interested_in:, min_age:, max_age:)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, gender:,
        birthdate: age.years.ago.to_date, status: :active, visibility: :visible
      )
      ProfilePreference.create!(brand:, user:, profile:, interested_in:, min_age:, max_age:)
      profile
    end
  end
end
