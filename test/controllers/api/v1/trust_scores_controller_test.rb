require "test_helper"

class Api::V1::TrustScoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: @brand, host: "date9ja.test")
    @user = User.create!
    BrandMembership.create!(brand: @brand, user: @user)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "date9ja.test"
  end

  test "requires authentication" do
    get "/api/v1/trust_score"

    assert_response :unauthorized
  end

  test "returns a score of 0 and an empty breakdown with no ledger rows" do
    get "/api/v1/trust_score", headers: bearer_headers(@token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 0, body.fetch("score")
    assert_equal [], body.fetch("breakdown")
  end

  test "returns the derived score with a labeled, most-recent-first breakdown" do
    TrustEvent.create!(brand: @brand, user: @user, event_type: "realme_email_approved", points: 25, idempotency_key: "e1", occurred_at: 2.days.ago)
    TrustAdjustment.create!(brand: @brand, user: @user, points: -10, reason_code: "policy_violation", idempotency_key: "a1", occurred_at: 1.day.ago)

    get "/api/v1/trust_score", headers: bearer_headers(@token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 15, body.fetch("score")
    assert_equal(
      [
        { "kind" => "adjustment", "type" => "policy_violation", "label" => "Policy violation", "points" => -10, "applies" => true },
        { "kind" => "event", "type" => "realme_email_approved", "label" => "Email verification", "points" => 25, "applies" => true }
      ],
      body.fetch("breakdown").map { |entry| entry.except("occurred_at") }
    )
  end

  test "never surfaces another user's trust score" do
    other_user = User.create!
    BrandMembership.create!(brand: @brand, user: other_user)
    TrustEvent.create!(brand: @brand, user: other_user, event_type: "realme_email_approved", points: 25, idempotency_key: "e1", occurred_at: Time.current)

    get "/api/v1/trust_score", headers: bearer_headers(@token)

    assert_response :success
    assert_equal 0, JSON.parse(response.body).fetch("score")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
