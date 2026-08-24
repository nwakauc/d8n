require "test_helper"

module Trust
  class BlockProfileConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @brand = Brand.create!(slug: "block-lock-#{SecureRandom.hex(6)}", name: "Block Lock Test")
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
      Profile.where(brand: @brand).delete_all
      BrandMembership.where(brand: @brand).delete_all
      User.where(id: user_ids).delete_all
      @brand.destroy!
    end

    test "blocking wins safely against a reciprocal like" do
      Like.create!(brand: @brand, liker_profile: @target, liked_profile: @viewer)

      outcomes = race(
        -> { BlockProfile.call(user: @viewer.user, brand: @brand, target_public_id: @target.public_id) },
        -> {
          Matching::LikeProfile.call(
            user: @viewer.user,
            brand: @brand,
            target_public_id: @target.public_id,
            eligibility_policy: D8n::Platform::Brands::Hookus::ELIGIBILITY_POLICY
          )
        }
      )

      assert_block_succeeded(outcomes)
      assert_race_outcomes(
        outcomes,
        success_class: Matching::LikeProfile::Result,
        error_class: Matching::InteractionError,
        error_code: :profile_unavailable
      )
      assert ProfileBlock.kept.exists?(brand: @brand, blocker_profile: @viewer, blocked_profile: @target)
      assert_empty Like.kept.where(brand: @brand, liker_profile_id: [ @viewer.id, @target.id ])
      assert_empty Match.kept.status_active.where(brand: @brand)
    end

    test "blocking wins safely against conversation creation" do
      match = create_match

      outcomes = race(
        -> { BlockProfile.call(user: @viewer.user, brand: @brand, target_public_id: @target.public_id) },
        -> {
          Messaging::StartConversation.call(
            user: @target.user,
            brand: @brand,
            match_public_id: match.public_id
          )
        }
      )

      assert_block_succeeded(outcomes)
      assert_race_outcomes(
        outcomes,
        success_class: Messaging::StartConversation::Result,
        error_class: Messaging::AccessError,
        error_code: :conversation_unavailable
      )
      assert_predicate match.reload, :status_ended?
      assert_raises(Messaging::AccessError) do
        Messaging::MatchAccess.find!(
          user: @target.user,
          brand: @brand,
          match_public_id: match.public_id
        )
      end
      assert_empty Messaging::ConversationList.call(user: @target.user, brand: @brand).conversations
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

    def assert_block_succeeded(outcomes)
      assert outcomes.any? { |outcome| outcome.is_a?(BlockProfile::Result) }, outcomes.map(&:inspect).join("\n")
    end

    def assert_race_outcomes(outcomes, success_class:, error_class:, error_code:)
      valid = outcomes.all? do |outcome|
        outcome.is_a?(BlockProfile::Result) || outcome.is_a?(success_class) ||
          (outcome.is_a?(error_class) && outcome.code == error_code)
      end
      assert valid, outcomes.map(&:inspect).join("\n")
    end
  end
end
