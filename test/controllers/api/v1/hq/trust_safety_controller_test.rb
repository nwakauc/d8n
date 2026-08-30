require "test_helper"

class Api::V1::Hq::TrustSafetyControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hq-ts-api", name: "HQ TS API")
    BrandDomain.create!(brand: @brand, host: "hq-ts-api.test")
    @reporter = create_profile(@brand, "Reporter")
    @reported = create_profile(@brand, "Reported")
    @admin, @token = create_admin(@brand)
    host! "hq-ts-api.test"
  end

  test "all endpoints require an authenticated assigned moderator" do
    get "/api/v1/hq/trust_safety/overview"
    assert_response :unauthorized

    ordinary_token, = Session.issue!(brand: @brand, user: @reporter.user)
    get "/api/v1/hq/trust_safety/repeat_offenders", headers: bearer_headers(ordinary_token)
    assert_response :forbidden

    other_brand = Brand.create!(slug: "hq-ts-api-other-admin", name: "Other Admin Brand")
    _admin, wrong_brand_token = create_admin(@brand, assign_brand: other_brand)
    get "/api/v1/hq/trust_safety/enforcements", headers: bearer_headers(wrong_brand_token)
    assert_response :forbidden
  end

  test "overview is brand-scoped, truthful about SLA, and audited" do
    create_report(@brand, @reporter, @reported, reason: :harassment)
    other_brand = Brand.create!(slug: "hq-ts-api-other", name: "Other")
    other_reporter = create_profile(other_brand, "Other Reporter")
    other_reported = create_profile(other_brand, "Other Reported")
    create_report(other_brand, other_reporter, other_reported, reason: :spam)

    assert_difference -> { SecurityEvent.where(event_type: "hq.trust_safety_overview_viewed").count }, 1 do
      get "/api/v1/hq/trust_safety/overview", headers: bearer_headers(@token)
    end
    assert_response :success

    overview = JSON.parse(response.body).fetch("overview")
    assert_equal @brand.slug, overview.fetch("brand")
    assert_equal 1, overview.dig("reports", "total")
    assert_equal 1, overview.dig("reports", "by_reason", "harassment")
    assert_equal 0, overview.dig("reports", "by_reason", "spam")
    assert_equal "not_configured", overview.dig("reports", "sla_status")
    assert_nil overview.dig("reports", "overdue")

    audit = SecurityEvent.where(event_type: "hq.trust_safety_overview_viewed").last
    assert_equal @admin.id, audit.metadata.fetch("admin_user_id")
    assert audit.metadata.fetch("session_id").present?
  end

  test "repeat offenders are brand-scoped, bounded, and link to Member 360" do
    create_report(@brand, @reporter, @reported, reason: :harassment)
    create_report(@brand, create_profile(@brand, "Second Reporter"), @reported, reason: :harassment)

    assert_difference -> { SecurityEvent.where(event_type: "hq.trust_safety_repeat_offenders_viewed").count }, 1 do
      get "/api/v1/hq/trust_safety/repeat_offenders", headers: bearer_headers(@token)
    end
    assert_response :success

    body = JSON.parse(response.body)
    offender = body.fetch("repeat_offenders").sole
    assert_equal @reported.public_id, offender.fetch("profile_id")
    assert_equal @reported.public_id, offender.fetch("member_360_lookup")
    assert_equal 2, offender.fetch("report_count")
    assert_equal 2, body.fetch("minimum_reports")
  end

  test "enforcement history is brand-scoped, filtered, paginated, and audited" do
    first = create_enforcement(@brand, @reported, reverted_at: Time.current)
    active_profile = create_profile(@brand, "Active Target")
    second = create_enforcement(@brand, active_profile)
    other_brand = Brand.create!(slug: "hq-ts-api-enforcement-other", name: "Other")
    other_profile = create_profile(other_brand, "Other Target")
    create_enforcement(other_brand, other_profile)
    first.update_columns(created_at: 2.hours.ago)
    second.update_columns(created_at: 1.hour.ago)

    assert_difference -> { SecurityEvent.where(event_type: "hq.trust_safety_enforcements_viewed").count }, 1 do
      get "/api/v1/hq/trust_safety/enforcements", headers: bearer_headers(@token), params: { state: "active", limit: 1 }
    end
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal [ second.id ], body.fetch("enforcements").pluck("id")
    assert_nil body.fetch("next_cursor")
  end

  test "invalid filters, limits, and cursors return stable 422 errors" do
    get "/api/v1/hq/trust_safety/enforcements", headers: bearer_headers(@token), params: { state: "unknown" }
    assert_response :unprocessable_entity
    assert_equal "invalid_filter", JSON.parse(response.body).fetch("error")

    get "/api/v1/hq/trust_safety/repeat_offenders", headers: bearer_headers(@token), params: { limit: 0 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")

    get "/api/v1/hq/trust_safety/enforcements", headers: bearer_headers(@token), params: { cursor: "invalid" }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand, display_name)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(
      brand:, user:, brand_membership: membership, display_name:,
      birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
  end

  def create_admin(login_brand, assign_brand: login_brand)
    user = User.create!
    BrandMembership.create!(brand: login_brand, user:)
    admin = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: "moderator")
    AdminAssignment.create!(admin_user: admin, brand: assign_brand, admin_role: role, status: :active)
    token = issue_mfa_verified_admin_session!(user:, brand: login_brand, admin_user: admin)
    [ admin, token ]
  end

  def create_report(brand, reporter, reported, reason:)
    Report.create!(
      brand:, reporter_profile: reporter, reported_profile: reported,
      reason:, target_type: :profile, status: :open
    )
  end

  def create_enforcement(brand, profile, reverted_at: nil)
    AccountEnforcement.create!(
      brand:, user: profile.user, brand_membership: profile.brand_membership,
      profile:, admin_user: @admin, reason: "test", reverted_at:
    )
  end
end
