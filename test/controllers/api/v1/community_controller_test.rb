require "test_helper"

class Api::V1::CommunityControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: @brand, host: "date9ja.test")
    @profile, @token = create_member(brand: @brand, display_name: "Ada")
    host! "date9ja.test"
  end

  test "submission stays private until an audited brand moderator approval" do
    post "/api/v1/community/questions", headers: bearer_headers(@token), params: {
      category: "marriage", body: "How should we discuss family expectations?", anonymous: true
    }, as: :json

    assert_response :created
    question = CommunityQuestion.last
    assert question.status_pending?
    assert_equal "pending", response.parsed_body.dig("question", "status")

    get "/api/v1/community/questions", headers: bearer_headers(@token)
    assert_response :success
    assert_empty response.parsed_body.fetch("questions")

    get "/api/v1/community/me/submissions", headers: bearer_headers(@token)
    assert_response :success
    assert_equal question.public_id, response.parsed_body.dig("questions", 0, "id")

    admin, admin_token = create_admin(brand: @brand)
    assert_difference -> { SecurityEvent.where(event_type: "admin.community_moderated").count }, 1 do
      patch "/api/v1/admin/community/questions/#{question.public_id}",
        headers: bearer_headers(admin_token), params: { status: "approved" }, as: :json
    end
    assert_response :success
    assert response.parsed_body.fetch("transitioned")
    assert_equal admin, question.reload.reviewed_by_admin_user

    get "/api/v1/community/questions", headers: bearer_headers(@token)
    payload = response.parsed_body.dig("questions", 0)
    assert_equal question.public_id, payload.fetch("id")
    assert_equal({ "display_name" => "Anonymous" }, payload.fetch("author"))
    assert_not payload.key?("status")
    assert_not_includes response.body, "moderation_note"
  end

  test "moderation is idempotent and rejects cross-brand records" do
    question = create_question(profile: @profile, status: :pending)
    _admin, admin_token = create_admin(brand: @brand)

    patch "/api/v1/admin/community/questions/#{question.public_id}",
      headers: bearer_headers(admin_token), params: { status: "approved" }, as: :json
    assert_response :success

    assert_no_difference -> { SecurityEvent.where(event_type: "admin.community_moderated").count } do
      patch "/api/v1/admin/community/questions/#{question.public_id}",
        headers: bearer_headers(admin_token), params: { status: "approved" }, as: :json
    end
    assert_response :success
    assert_not response.parsed_body.fetch("transitioned")

    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    other_profile, = create_member(brand: other_brand)
    foreign = create_question(profile: other_profile, status: :pending)
    patch "/api/v1/admin/community/questions/#{foreign.public_id}",
      headers: bearer_headers(admin_token), params: { status: "approved" }, as: :json
    assert_response :not_found
  end

  test "moderation queue is MFA-protected, brand scoped, and contains reviewable content" do
    question = create_question(profile: @profile, status: :pending)
    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    other_profile, = create_member(brand: other_brand)
    create_question(profile: other_profile, status: :pending)
    _admin, admin_token = create_admin(brand: @brand)

    get "/api/v1/admin/community/questions", headers: bearer_headers(admin_token)

    assert_response :success
    submissions = response.parsed_body.fetch("submissions")
    assert_equal 1, submissions.size
    assert_equal question.public_id, submissions.first.fetch("id")
    assert_equal question.body, submissions.first.dig("content", "body")
    assert_equal @profile.public_id, submissions.first.dig("content", "submitted_by", "id")
    assert_not submissions.first.fetch("content").key?("moderation_note")
    assert_match(/private/, response.headers.fetch("Cache-Control"))
  end

  test "approved material edit returns a submission to private moderation" do
    question = create_question(profile: @profile, status: :approved)

    patch "/api/v1/community/questions/#{question.public_id}",
      headers: bearer_headers(@token), params: { body: "A materially revised question" }, as: :json

    assert_response :success
    question.reload
    assert question.status_pending?
    assert_nil question.published_at
    assert_equal "pending", response.parsed_body.dig("question", "status")
  end

  test "another member cannot edit an owner's submission" do
    question = create_question(profile: @profile, status: :approved)
    _other, other_token = create_member(brand: @brand)

    patch "/api/v1/community/questions/#{question.public_id}",
      headers: bearer_headers(other_token), params: { body: "Hijacked" }, as: :json

    assert_response :not_found
    assert_not_equal "Hijacked", question.reload.body
  end

  test "event RSVP is idempotent, capacity safe, and attendee list is organizer-only" do
    event = CommunityEvent.create!(
      brand: @brand, organizer_profile: @profile, title: "Lagos dinner",
      description: "A small hosted dinner", city: "Lagos", starts_at: 2.days.from_now,
      capacity: 1, status: :approved, published_at: Time.current
    )
    attendee, attendee_token = create_member(brand: @brand, display_name: "Tobi")
    _other, other_token = create_member(brand: @brand)

    post "/api/v1/community/events/#{event.public_id}/rsvp", headers: bearer_headers(attendee_token)
    assert_response :created
    assert_equal 1, response.parsed_body.dig("rsvp", "count")

    post "/api/v1/community/events/#{event.public_id}/rsvp", headers: bearer_headers(attendee_token)
    assert_response :success
    assert_equal 1, event.community_event_rsvps.kept.status_attending.count

    post "/api/v1/community/events/#{event.public_id}/rsvp", headers: bearer_headers(other_token)
    assert_response :not_found

    get "/api/v1/community/events/#{event.public_id}/attendees", headers: bearer_headers(attendee_token)
    assert_response :not_found

    get "/api/v1/community/events/#{event.public_id}/attendees", headers: bearer_headers(@token)
    assert_response :success
    assert_equal attendee.public_id, response.parsed_body.dig("attendees", 0, "id")
  end

  test "Circle discussion requires active same-brand membership" do
    circle = CommunityCircle.create!(
      brand: @brand, creator_profile: @profile, name: "Intentional dating",
      description: "A moderated room", category: "dating", status: :approved,
      published_at: Time.current
    )

    post "/api/v1/community/circles/#{circle.public_id}/posts",
      headers: bearer_headers(@token), params: { body: "Hello" }, as: :json
    assert_response :not_found

    post "/api/v1/community/circles/#{circle.public_id}/membership", headers: bearer_headers(@token)
    assert_response :created
    post "/api/v1/community/circles/#{circle.public_id}/posts",
      headers: bearer_headers(@token), params: { body: "Hello" }, as: :json
    assert_response :created

    delete "/api/v1/community/circles/#{circle.public_id}/membership", headers: bearer_headers(@token)
    assert_response :no_content
    get "/api/v1/community/circles/#{circle.public_id}/posts", headers: bearer_headers(@token)
    assert_response :not_found
  end

  test "a visible Community target uses Trust reporting with bounded evidence" do
    author, = create_member(brand: @brand, display_name: "Author")
    question = create_question(profile: author, status: :approved)

    post "/api/v1/reports", headers: bearer_headers(@token), params: {
      target_type: "community_question", target_id: question.public_id,
      reason: "inappropriate_content", details: "Please review"
    }, as: :json

    assert_response :created
    report = Report.last
    assert report.target_community_question?
    assert_equal author, report.reported_profile
    assert_equal question.body, report.evidence.fetch("body")
    assert_not report.evidence.key?("moderation_note")

    _second_reporter, second_token = create_member(brand: @brand)
    assert_difference -> { Report.where(target_type: :community_question, target_id: question.id).count }, 1 do
      post "/api/v1/reports", headers: bearer_headers(second_token), params: {
        target_type: "community_question", target_id: question.public_id,
        reason: "spam"
      }, as: :json
    end
    assert_response :created
  end

  test "Community is disabled by default for another brand" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand:, host: "hookus.test")
    _profile, token = create_member(brand:)
    host! "hookus.test"

    get "/api/v1/community/questions", headers: bearer_headers(token)

    assert_response :not_found
    assert_equal "community_not_configured", response.parsed_body.fetch("error")
  end

  test "invalid submissions return a controlled validation response" do
    post "/api/v1/community/questions", headers: bearer_headers(@token), params: {
      category: "not-real", body: "Question"
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "community_validation_failed", response.parsed_body.fetch("error")
    assert_includes response.parsed_body.fetch("fields"), "category"
  end

  private

  def create_member(brand:, display_name: "Member")
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(brand:, user:, brand_membership: membership, display_name:)
    token, = Session.issue!(brand:, user:)
    [ profile, token ]
  end

  def create_admin(brand:)
    user = User.create!
    BrandMembership.create!(brand:, user:)
    admin = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: "moderator")
    AdminAssignment.create!(admin_user: admin, brand:, admin_role: role, status: :active)
    [ admin, issue_mfa_verified_admin_session!(user:, brand:, admin_user: admin) ]
  end

  def create_question(profile:, status:)
    CommunityQuestion.create!(
      brand: profile.brand, author_profile: profile, category: "dating",
      body: "How do I date intentionally?", closes_at: 7.days.from_now,
      status:, published_at: (Time.current if status == :approved)
    )
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
