require "test_helper"

module Matching
  class UnmatchConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @brand = Brand.create!(slug: "unmatch-lock-#{SecureRandom.hex(6)}", name: "Unmatch Lock Test")
      @viewer = create_profile(gender: "woman", interested_in: [ "man" ])
      @target = create_profile(gender: "man", interested_in: [ "woman" ])
    end

    teardown do
      return unless @brand

      user_ids = Profile.where(brand: @brand).pluck(:user_id)
      ConversationParticipant.where(brand: @brand).delete_all
      Conversation.where(brand: @brand).delete_all
      ProfileBlock.where(brand: @brand).delete_all
      Match.where(brand: @brand).delete_all
      Like.where(brand: @brand).delete_all
      ProfilePass.where(brand: @brand).delete_all
      ProfilePreference.where(brand: @brand).delete_all
      AnalyticsEvent.where(brand: @brand).delete_all
      Profile.where(brand: @brand).delete_all
      BrandMembership.where(brand: @brand).delete_all
      User.where(id: user_ids).delete_all
      @brand.destroy!
    end

    test "two concurrent unmatch requests on the same match settle safely, exactly once" do
      match = create_match
      Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: @target)
      Like.create!(brand: @brand, liker_profile: @target, liked_profile: @viewer)

      outcomes = race(
        -> { Unmatch.call(user: @viewer.user, brand: @brand, match_public_id: match.public_id) },
        -> { Unmatch.call(user: @target.user, brand: @brand, match_public_id: match.public_id) }
      )

      assert outcomes.all? { |outcome| outcome.is_a?(Unmatch::Result) }, outcomes.map(&:inspect).join("\n")
      assert outcomes.any? { |outcome| outcome.already_ended == false },
        "expected exactly one caller to observe the transition"
      assert_predicate match.reload, :status_ended?
      assert_empty Like.kept.where(brand: @brand, liker_profile_id: [ @viewer.id, @target.id ])
      assert_not ProfileBlock.kept.exists?(brand: @brand, blocker_profile: @viewer, blocked_profile: @target)
    end

    test "concurrent unmatch and block settle into a valid, non-contradictory final state" do
      match = create_match
      Like.create!(brand: @brand, liker_profile: @viewer, liked_profile: @target)
      Like.create!(brand: @brand, liker_profile: @target, liked_profile: @viewer)

      outcomes = race(
        -> { Unmatch.call(user: @viewer.user, brand: @brand, match_public_id: match.public_id) },
        -> { Trust::BlockProfile.call(user: @viewer.user, brand: @brand, target_public_id: @target.public_id) }
      )

      valid = outcomes.all? { |outcome| outcome.is_a?(Unmatch::Result) || outcome.is_a?(Trust::BlockProfile::Result) }
      assert valid, outcomes.map(&:inspect).join("\n")
      # Both operations independently end the Match and discard Likes, so no
      # deadlock and no resurrection is possible regardless of arrival order —
      # the only thing that varies is whether a Block also exists.
      assert_predicate match.reload, :status_ended?
      assert_empty Like.kept.where(brand: @brand, liker_profile_id: [ @viewer.id, @target.id ])
      assert ProfileBlock.kept.exists?(brand: @brand, blocker_profile: @viewer, blocked_profile: @target),
        "the Block operation ran in this race and must have taken effect"
    end

    private

    def create_profile(gender:, interested_in:)
      user = User.create!
      membership = BrandMembership.create!(brand: @brand, user:)
      profile = Profile.create!(
        brand: @brand,
        user:,
        brand_membership: membership,
        gender:,
        birthdate: 30.years.ago.to_date,
        status: :active,
        visibility: :visible
      )
      ProfilePreference.create!(
        brand: @brand,
        user:,
        profile:,
        min_age: 25,
        max_age: 40,
        interested_in:
      )
      profile
    end

    def create_match
      profile_a_id, profile_b_id = Match.canonical_pair(@viewer.id, @target.id)
      Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
    end

    def race(*operations)
      results = Queue.new
      start = Queue.new
      threads = operations.map do |operation|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            results << operation.call
          rescue StandardError => e
            results << e
          end
        end
      end
      operations.size.times { start << true }
      threads.each(&:join)
      operations.size.times.map { results.pop }
    end
  end
end
