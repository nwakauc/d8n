require "test_helper"

class Api::V1::Hq::ProductIntelligenceControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "product-intelligence", name: "Product Intelligence")
    BrandDomain.create!(brand: @brand, host: "product-intelligence.test")
    @user = User.create!
    BrandMembership.create!(brand: @brand, user: @user)
    @admin = AdminUser.create!(user: @user, status: :active)
    AdminAssignment.create!(
      admin_user: @admin, brand: @brand,
      admin_role: AdminRole.find_or_create_by!(name: "analyst"), status: :active
    )
    @token = issue_mfa_verified_admin_session!(user: @user, brand: @brand, admin_user: @admin)
    host! "product-intelligence.test"
  end

  test "returns a bounded cohort funnel with explicit unavailable onboarding" do
    get "/api/v1/hq/product_intelligence/funnel", headers: headers, params: { window: "last_7d" }

    assert_response :success
    funnel = JSON.parse(response.body).fetch("funnel")
    assert_equal "product-intelligence", funnel.fetch("brand")
    assert_equal "last_7d", funnel.fetch("window")
    assert_equal "available", funnel.fetch("stages").first.fetch("status")
    assert_equal "unavailable", funnel.fetch("stages")[1].fetch("status")
  end

  test "rejects an unsupported window safely" do
    get "/api/v1/hq/product_intelligence/trends", headers: headers, params: { window: "all_time" }

    assert_response :bad_request
    assert_equal "invalid_window", JSON.parse(response.body).fetch("error")
  end

  test "returns daily trend points for a bounded window" do
    AnalyticsEvent.create!(
      event_id: SecureRandom.uuid, event_type: "member.registered", brand: @brand,
      user: @user, occurred_at: Time.utc(2026, 9, 1, 8, 0, 0),
      idempotency_key: "trend-event", properties: {}
    )

    get "/api/v1/hq/product_intelligence/trends", headers: headers, params: { window: "today" }

    assert_response :success
    trends = JSON.parse(response.body).fetch("trends")
    registrations = trends.fetch("series").find { |series| series.fetch("id") == "registrations" }
    assert_equal 1, registrations.fetch("points").values.sum
  end

  test "requires analytics capability" do
    @admin.admin_assignments.first.update!(admin_role: AdminRole.find_or_create_by!(name: "support"))

    get "/api/v1/hq/product_intelligence/funnel", headers: headers

    assert_response :forbidden
  end

  private

  def headers
    { "Authorization" => "Bearer #{@token}" }
  end
end
