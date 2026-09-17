require "test_helper"

module Date9ja
  module Import
    class ConversationParticipantBackfillTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        @alice = profile("alice", "woman")
        @bob = profile("bob", "man")
      end

      test "creates missing participants for a conversation that predates participant-row creation" do
        match = Match.create!(brand: @brand, profile_a: @alice, profile_b: @bob)
        conversation = Conversation.create!(brand: @brand, match:)
        assert_equal 0, conversation.conversation_participants.count

        result = ConversationParticipantBackfill.call(brand: @brand)

        assert_equal 1, result.conversations_checked
        assert_equal 2, result.participants_created
        assert_equal [ @alice.id, @bob.id ].sort, conversation.reload.conversation_participants.pluck(:profile_id).sort
      end

      test "is idempotent -- a conversation with participants already present is left alone" do
        match = Match.create!(brand: @brand, profile_a: @alice, profile_b: @bob)
        conversation = Conversation.create!(brand: @brand, match:)
        [ @alice, @bob ].each { |profile| conversation.conversation_participants.create!(profile:, user: profile.user, brand: @brand) }

        result = ConversationParticipantBackfill.call(brand: @brand)

        assert_equal 0, result.participants_created
        assert_equal 2, conversation.reload.conversation_participants.count
      end

      test "backfills only the missing side when one participant already exists" do
        match = Match.create!(brand: @brand, profile_a: @alice, profile_b: @bob)
        conversation = Conversation.create!(brand: @brand, match:)
        conversation.conversation_participants.create!(profile: @alice, user: @alice.user, brand: @brand)

        result = ConversationParticipantBackfill.call(brand: @brand)

        assert_equal 1, result.participants_created
        assert_equal [ @alice.id, @bob.id ].sort, conversation.reload.conversation_participants.pluck(:profile_id).sort
      end

      private

      def profile(name, gender)
        user = User.create!
        membership = BrandMembership.create!(brand: @brand, user:)
        Profile.create!(brand: @brand, user:, brand_membership: membership,
          display_name: name, birthdate: 30.years.ago.to_date, gender:)
      end
    end
  end
end
