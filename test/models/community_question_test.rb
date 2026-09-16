require "test_helper"

class CommunityQuestionTest < ActiveSupport::TestCase
  test "model and database reject a cross-brand author" do
    brand, profile = member_profile("date9ja")
    other_brand, = member_profile("hookus")
    question = CommunityQuestion.new(
      brand: other_brand, author_profile: profile, category: "dating",
      body: "How do I date intentionally?", closes_at: 7.days.from_now
    )

    assert_not question.valid?
    assert_includes question.errors[:author_profile], "must belong to the question brand"

    assert_raises ActiveRecord::InvalidForeignKey do
      CommunityQuestion.insert_all!([ {
        brand_id: other_brand.id,
        author_profile_id: profile.id,
        public_id: SecureRandom.uuid,
        category: "dating",
        body: "Cross-tenant",
        anonymous: true,
        status: 0,
        selection_status: 0,
        closes_at: 7.days.from_now,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end

    assert_equal brand, profile.brand
  end

  test "selected answer must belong to the same question" do
    brand, profile = member_profile("date9ja")
    first = create_question(brand:, profile:)
    second = create_question(brand:, profile:)
    answer = CommunityAnswer.create!(
      brand:, community_question: second, author_profile: profile, body: "An answer"
    )

    first.selected_answer = answer

    assert_not first.valid?
    assert_includes first.errors[:selected_answer], "must belong to the question"
  end

  private

  def member_profile(slug)
    brand = Brand.create!(slug:, name: slug.titleize)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    [ brand, Profile.create!(brand:, user:, brand_membership: membership) ]
  end

  def create_question(brand:, profile:)
    CommunityQuestion.create!(
      brand:, author_profile: profile, category: "dating", body: "Question",
      closes_at: 7.days.from_now
    )
  end
end
