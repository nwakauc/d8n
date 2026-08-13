require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    @first = create_profile(@brand)
    @second = create_profile(@brand)
    profile_a_id, profile_b_id = Match.canonical_pair(@first.id, @second.id)
    @match = Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
  end

  test "assigns a public UUID and permits one conversation per match" do
    conversation = Conversation.create!(brand: @brand, match: @match)

    assert_match Profile::PUBLIC_ID_FORMAT, conversation.public_id
    assert_not Conversation.new(brand: @brand, match: @match).valid?
  end

  test "database rejects a conversation whose match belongs to another brand" do
    other_brand = Brand.create!(slug: "other", name: "Other")

    assert_raises ActiveRecord::InvalidForeignKey do
      Conversation.insert_all!([ {
        brand_id: other_brand.id,
        match_id: @match.id,
        public_id: SecureRandom.uuid,
        status: Conversation.statuses.fetch("active"),
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "database rejects a participant with mismatched profile ownership" do
    conversation = Conversation.create!(brand: @brand, match: @match)

    assert_raises ActiveRecord::InvalidForeignKey do
      ConversationParticipant.insert_all!([ {
        conversation_id: conversation.id,
        profile_id: @first.id,
        user_id: @second.user_id,
        brand_id: @brand.id,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "rejects a same-brand profile that is not in the match" do
    conversation = Conversation.create!(brand: @brand, match: @match)
    outsider = create_profile(@brand)
    participant = ConversationParticipant.new(
      conversation:, profile: outsider, user: outsider.user, brand: @brand
    )

    assert_not participant.valid?
    assert_includes participant.errors[:profile], "must participate in the conversation match"
  end

  private

  def create_profile(brand)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end
end
