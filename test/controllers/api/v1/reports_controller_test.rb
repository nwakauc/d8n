require "test_helper"

class Api::V1::ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @viewer = create_profile(brand: @brand, display_name: "Ada")
    @target = create_profile(brand: @brand, display_name: "Sam")
    @token, = Session.issue!(brand: @brand, user: @viewer.user)
    host! "hookus.test"
  end

  test "requires authentication" do
    post "/api/v1/profiles/#{@target.public_id}/report", params: { reason: "spam" }
    assert_response :unauthorized
  end

  test "files a report and records a security event" do
    assert_difference -> { Report.count } => 1, -> { SecurityEvent.where(event_type: "trust.profile_reported").count } => 1 do
      post "/api/v1/profiles/#{@target.public_id}/report",
        headers: bearer_headers(@token), params: { reason: "harassment", note: "sent abusive messages" }
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert body.fetch("reported")
    assert body.fetch("created")

    report = Report.sole
    assert_equal @viewer.id, report.reporter_profile_id
    assert_equal @target.id, report.reported_profile_id
    assert report.reason_harassment?
    assert report.status_open?
    assert_equal "sent abusive messages", report.note
  end

  test "is idempotent while an open report exists" do
    post "/api/v1/profiles/#{@target.public_id}/report",
      headers: bearer_headers(@token), params: { reason: "spam" }
    assert_response :created

    assert_no_difference -> { Report.count } do
      post "/api/v1/profiles/#{@target.public_id}/report",
        headers: bearer_headers(@token), params: { reason: "harassment" }
    end
    assert_response :success
    assert_not JSON.parse(response.body).fetch("created")
    # The original open report is authoritative; a repeat does not mutate it.
    assert Report.sole.reason_spam?
  end

  test "allows a fresh report once the prior one is resolved" do
    Report.create!(brand: @brand, reporter_profile: @viewer, reported_profile: @target,
      reason: :spam, status: :dismissed)

    assert_difference -> { Report.open_reports.count } => 1 do
      post "/api/v1/profiles/#{@target.public_id}/report",
        headers: bearer_headers(@token), params: { reason: "fake_profile" }
    end
    assert_response :created
  end

  test "rejects a missing or unknown reason without creating a report" do
    [ nil, "", "not_a_reason" ].each do |reason|
      assert_no_difference -> { Report.count } do
        post "/api/v1/profiles/#{@target.public_id}/report",
          headers: bearer_headers(@token), params: { reason: }.compact
      end
      assert_response :unprocessable_entity
      assert_equal "invalid_reason", JSON.parse(response.body).fetch("error")
    end
  end

  test "uses the same unavailable response for self unknown and cross-brand targets" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_profile = create_profile(brand: other_brand)

    [ @viewer.public_id, SecureRandom.uuid, other_profile.public_id ].each do |profile_id|
      assert_no_difference -> { Report.count } do
        post "/api/v1/profiles/#{profile_id}/report",
          headers: bearer_headers(@token), params: { reason: "spam" }
      end
      assert_response :not_found
      assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
    end
  end

  test "does not report a soft-deleted target" do
    @target.update!(deleted_at: Time.current)

    assert_no_difference -> { Report.count } do
      post "/api/v1/profiles/#{@target.public_id}/report",
        headers: bearer_headers(@token), params: { reason: "spam" }
    end
    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "reporting never changes the target's visibility or moderation state" do
    # Reporting must not reintroduce an approval gate or hide the target; it is
    # only an audit signal. ReportProfile touches neither the profile's
    # visibility/status nor any photo state.
    post "/api/v1/profiles/#{@target.public_id}/report",
      headers: bearer_headers(@token), params: { reason: "inappropriate_content" }
    assert_response :created

    @target.reload
    assert_predicate @target, :visible?
    assert_predicate @target, :active?
    assert_not_predicate @target, :suspended?
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
    ProfilePreference.create!(
      brand:, user:, profile:, min_age: 18, max_age: 80, interested_in: [ "person" ]
    )
    profile
  end
end
