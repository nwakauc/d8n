require "test_helper"

module Matching
  module Find
    class DatezaFindConcurrencyTest < ActiveSupport::TestCase
      self.use_transactional_tests = false

      test "concurrent disjoint Find queries cannot allocate more than ten unique exposures" do
        brand = Brand.create!(slug: "dateza", name: "DateZA")
        viewer = create_profile(brand:, gender: "woman", age: 30, min_age: 18, max_age: 60)
        10.times { create_profile(brand:, gender: "man", age: 25, min_age: 18, max_age: 60) }
        10.times { create_profile(brand:, gender: "man", age: 45, min_age: 18, max_age: 60) }
        results = Queue.new
        start = Queue.new

        threads = [ { max_age: 30 }, { min_age: 40 } ].map do |filter|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              start.pop
              results << Search.call(user: viewer.user, brand:, **filter)
            rescue StandardError => e
              results << e
            end
          end
        end
        2.times { start << true }
        threads.each(&:join)
        outcomes = 2.times.map { results.pop }

        assert outcomes.none? { |outcome| outcome.is_a?(StandardError) }, outcomes.map(&:inspect).join("\n")
        assert_equal 10, outcomes.sum { |outcome| outcome.profiles.size }
        assert_equal 10, FindProfileExposure.where(brand:, brand_membership: viewer.brand_membership).count
        assert outcomes.all? { |outcome| outcome.allowance.fetch(:used) == 10 }
      ensure
        cleanup(brand) if brand
      end

      private

      def create_profile(brand:, gender:, age:, min_age:, max_age:)
        user = User.create!
        membership = BrandMembership.create!(brand:, user:)
        profile = Profile.create!(
          brand:, user:, brand_membership: membership, gender:, birthdate: age.years.ago.to_date,
          status: :active, visibility: :visible
        )
        interested_in = gender == "woman" ? [ "man" ] : [ "woman" ]
        ProfilePreference.create!(brand:, user:, profile:, interested_in:, min_age:, max_age:)
        profile
      end

      def cleanup(brand)
        user_ids = Profile.where(brand:).pluck(:user_id)
        FindProfileExposure.where(brand:).delete_all
        ProfilePreference.where(brand:).delete_all
        Profile.where(brand:).delete_all
        BrandMembership.where(brand:).delete_all
        User.where(id: user_ids).delete_all
        brand.destroy!
      end
    end
  end
end
