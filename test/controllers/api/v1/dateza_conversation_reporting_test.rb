require "test_helper"

# Proves message and conversation reporting are genuinely shared D8N CHAT/TRUST
# infrastructure: the same Trust::FileReport, Trust::ReportTargets::MessageTarget,
# and Trust::ReportTargets::ConversationTarget used by HookUs, reachable through
# the same generic POST /api/v1/reports, on a brand with no reporting code of its
# own.
class DatezaConversationReportingTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(
      slug: "dateza-chat", name: "DateZA", auth_methods: %w[phone_password email_password]
    )
    BrandDomain.create!(brand: @brand, host: "dateza-chat.test")
    host! "dateza-chat.test"
    @reporter = create_profile(brand: @brand, display_name: "Nomvula")
    @offender = create_profile(brand: @brand, display_name: "Sipho")
    @token, = Session.issue!(brand: @brand, user: @reporter.user)
  end

  test "a DateZA member reports a message and a conversation through the shared endpoint" do
    profile_a_id, profile_b_id = Match.canonical_pair(@reporter.id, @offender.id)
    match = Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
    conversation = Messaging::StartConversation.call(
      user: @reporter.user, brand: @brand, match_public_id: match.public_id
    ).conversation
    message = Message.create!(brand: @brand, conversation:, sender_profile: @offender, body: "gross")

    post "/api/v1/reports", headers: bearer_headers(@token),
      params: { target_type: "message", target_id: message.public_id, reason: "harassment" }
    assert_response :created
    assert_equal @offender.id, Report.sole.reported_profile_id

    post "/api/v1/reports", headers: bearer_headers(@token),
      params: { target_type: "conversation", target_id: conversation.public_id, reason: "harassment" }
    assert_response :created
    assert_equal 2, Report.count
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand:, display_name: nil)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, display_name:,
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand:, user:, profile:, min_age: 18, max_age: 80, interested_in: [ "person" ])
    profile
  end
end
