require "test_helper"

module Matching
  class StableDailySelectionConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "simultaneous first requests create one logical allocation without duplicate or excess candidates" do
      brand = Brand.create!(slug: "dateza", name: "DateZA")
      viewer = create_profile(brand:, gender: "woman")
      14.times { create_profile(brand:, gender: "man") }
      surface = D8n::Platform::BrandRegistry.fetch(brand:).surface("discovery.curated_daily")
      results = Queue.new
      ready = Queue.new
      start = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            results << StableDailySelection.call(
              user: viewer.user, brand:, surface:, now: Time.utc(2026, 8, 24, 12)
            )
          rescue StandardError => e
            results << e
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      assert outcomes.none? { |outcome| outcome.is_a?(StandardError) }, outcomes.map(&:inspect).join("\n")
      assert_equal 1, DiscoveryAllocation.where(brand:, brand_membership: viewer.brand_membership).count
      allocation = DiscoveryAllocation.where(brand:, brand_membership: viewer.brand_membership).sole
      assert_equal 10, allocation.allocation_candidates.count
      assert_equal 10, allocation.allocation_candidates.distinct.count(:candidate_profile_id)
      assert_equal (1..10).to_a, allocation.allocation_candidates.pluck(:position)
      assert_equal outcomes.first.profiles.map(&:id), outcomes.last.profiles.map(&:id)
    ensure
      cleanup(brand) if brand
    end

    private

    def create_profile(brand:, gender:)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, gender:, birthdate: 30.years.ago.to_date,
        status: :active, visibility: :visible
      )
      interested_in = gender == "woman" ? [ "man" ] : [ "woman" ]
      ProfilePreference.create!(brand:, user:, profile:, interested_in:, min_age: 18, max_age: 60)
      profile
    end

    def cleanup(brand)
      user_ids = Profile.where(brand:).pluck(:user_id)
      DiscoveryAllocationCandidate.where(brand:).delete_all
      DiscoveryAllocation.where(brand:).delete_all
      ProfilePreference.where(brand:).delete_all
      AnalyticsEvent.where(brand:).delete_all
      Profile.where(brand:).delete_all
      BrandMembership.where(brand:).delete_all
      User.where(id: user_ids).delete_all
      brand.destroy!
    end
  end
end
