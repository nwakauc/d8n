require "test_helper"

module Messaging
  class StartConversationConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "concurrent participant requests create one complete conversation" do
      brand = Brand.create!(slug: "conversation-lock-#{SecureRandom.hex(6)}", name: "Conversation Lock Test")
      first = create_profile(brand:)
      second = create_profile(brand:)
      profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
      match = Match.create!(brand:, profile_a_id:, profile_b_id:)
      results = Queue.new
      start = Queue.new

      threads = [ first, second ].map do |profile|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.pop
            results << StartConversation.call(
              user: profile.user,
              brand:,
              match_public_id: match.public_id
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
      assert_equal 1, Conversation.where(match:).count
      assert_equal 2, ConversationParticipant.where(conversation: Conversation.find_by!(match:)).count
      assert_equal [ false, true ], outcomes.map(&:created).sort_by(&:to_s)
    ensure
      if brand
        ConversationParticipant.where(brand:).delete_all
        Conversation.where(brand:).delete_all
        Match.where(brand:).delete_all
        ProfilePreference.where(brand:).delete_all
        Profile.where(brand:).delete_all
        BrandMembership.where(brand:).delete_all
        User.where(id: [ first&.user_id, second&.user_id ].compact).delete_all
        brand.destroy!
      end
    end

    private

    def create_profile(brand:)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      Profile.create!(brand:, user:, brand_membership: membership)
    end
  end
end
