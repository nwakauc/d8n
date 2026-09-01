require "test_helper"

class Api::V1::Hq::CommandCentreControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "command-centre", name: "Command Centre")
    BrandDomain.create!(brand: @brand, host: "command-centre.test")
    @admin, @token = create_admin(brand: @brand)
    host! "command-centre.test"
  end

  test "returns a current-brand health snapshot and audits it" do
    assert_difference -> { SecurityEvent.where(event_type: "hq.command_centre_health_viewed").count }, 1 do
      get "/api/v1/hq/command_centre/health", headers: bearer_headers(@token)
    end

    assert_response :success
    body = JSON.parse(response.body).fetch("brand_health")
    assert_equal "command-centre", body.fetch("brand")
    assert_equal "Africa/Johannesburg", body.fetch("time_zone")
    assert_equal 1, body.dig("audience", "memberships_total", "value")
    assert_equal "available", body.dig("profile_health", "activation_ratio", "status")
    assert_equal 0, body.dig("profile_health", "activation_ratio", "value")
  end

  test "compares only brands with an analytics-capable active assignment" do
    other = Brand.create!(slug: "command-centre-other", name: "Other")
    AdminAssignment.create!(
      admin_user: @admin, brand: other,
      admin_role: AdminRole.find_or_create_by!(name: "analyst"), status: :active
    )

    get "/api/v1/hq/command_centre/brands", headers: bearer_headers(@token)

    assert_response :success
    brands = JSON.parse(response.body).fetch("brands")
    assert_equal [ "command-centre", "command-centre-other" ], brands.map { |entry| entry.fetch("brand") }
    assert brands.all? { |entry| entry.fetch("accessible") }
  end

  test "requires analytics capability" do
    @admin.admin_assignments.first.update!(admin_role: AdminRole.find_or_create_by!(name: "support"))

    get "/api/v1/hq/command_centre/health", headers: bearer_headers(@token)

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
