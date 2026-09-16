require "test_helper"

module Matching
  class LikeProfileConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "concurrent reciprocal likes create exactly one canonical match" do
      brand = Brand.create!(slug: "matching-lock-#{SecureRandom.hex(6)}", name: "Matching Lock Test")
      first = create_profile(brand:, gender: "woman", interested_in: [ "man" ])
      second = create_profile(brand:, gender: "man", interested_in: [ "woman" ])
      results = Queue.new
      start = Queue.new

      threads = [ [ first, second ], [ second, first ] ].map do |viewer, target|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            results << LikeProfile.call(
              user: viewer.user,
              brand:,
              target_public_id: target.public_id,
              eligibility_policy: D8n::Platform::Brands::Hookus::ELIGIBILITY_POLICY
            )
          rescue StandardError => e
            results << e
          end
        end
      end
      2.times { start << true }
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      assert outcomes.none? { |outcome| outcome.is_a?(StandardError) }, outcomes.map(&:inspect).join("\n")
      assert_equal 2, Like.kept.where(brand:).count
      assert_equal 1, Match.kept.status_active.where(brand:).count
      match = Match.kept.status_active.find_by!(brand:)
      assert_operator match.profile_a_id, :<, match.profile_b_id
    ensure
      if brand
        Match.where(brand:).delete_all
        Like.where(brand:).delete_all
        ProfilePass.where(brand:).delete_all
        ProfilePreference.where(brand:).delete_all
        AnalyticsEvent.where(brand:).delete_all
        Profile.where(brand:).delete_all
        BrandMembership.where(brand:).delete_all
        brand.destroy!
      end
    end

    private

    def create_profile(brand:, gender:, interested_in:)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, gender:, birthdate: 30.years.ago.to_date,
        status: :active, visibility: :visible
      )
      ProfilePreference.create!(
        brand:, user:, profile:, min_age: 25, max_age: 40, interested_in:
      )
      profile
    end
  end
end
