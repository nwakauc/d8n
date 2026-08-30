require "test_helper"

class Api::V1::Hq::AnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "analytics-controller", name: "Analytics Controller")
    BrandDomain.create!(brand: @brand, host: "analytics.test")
    @admin, @token = create_admin(brand: @brand)
    host! "analytics.test"
  end

  test "returns current-brand analytics and audits the read" do
    user = User.create!
    BrandMembership.create!(brand: @brand, user:)
    Profile.create!(
      brand: @brand, user:, brand_membership: user.brand_memberships.first,
      display_name: "Woman", birthdate: 30.years.ago.to_date, gender: "woman", status: :active, visibility: :visible
    )

    assert_difference -> { SecurityEvent.where(event_type: "hq.analytics_overview_viewed").count }, 1 do
      get "/api/v1/hq/analytics/overview", headers: bearer_headers(@token)
    end
    assert_response :success

    overview = JSON.parse(response.body).fetch("overview")
    assert_equal "analytics-controller", overview.fetch("brand")
    assert_equal "Africa/Johannesburg", overview.fetch("time_zone")
    assert_equal 2, overview.fetch("total_registered_members")
    assert_equal 1, overview.dig("gender_split", "woman")
  end

  test "requires analytics capability" do
    role = AdminRole.create!(name: "trust_safety")
    @admin.admin_assignments.first.update!(admin_role: role)

    get "/api/v1/hq/analytics/overview", headers: bearer_headers(@token)
    assert_response :forbidden
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_admin(brand:)
    user = User.create!
    BrandMembership.create!(brand:, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: "founder")
    AdminAssignment.create!(admin_user:, brand:, admin_role: role, status: :active)
    token = issue_mfa_verified_admin_session!(user:, brand:, admin_user:)
    [ admin_user, token ]
  end
end
