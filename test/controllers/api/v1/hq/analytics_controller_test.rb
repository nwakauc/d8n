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

    # RealMe/trust distribution: canonical states only, counted over the one
    # real (non-admin) profile -- the admin user has no Profile and is
    # correctly excluded from both.
    assert_equal 1, overview.dig("realme_distribution", "not_started")
    assert_equal 0, overview.dig("realme_distribution", "full_badge")
    assert_equal 1, overview.dig("trust_summary", "members_scored")
    assert_equal 0, overview.dig("trust_summary", "average_score")
    assert_equal 0, overview.dig("trust_summary", "members_with_active_deduction")
  end

  test "realme_distribution correctly buckets full badge, messaging-eligible, and pending members" do
    badge_profile = create_verified_profile(check_types_approved: %w[selfie video government_id], email_verified: true)
    eligible_profile = create_verified_profile(check_types_approved: %w[selfie])
    pending_profile = create_verified_profile(check_types_approved: [], check_types_pending: %w[selfie])

    get "/api/v1/hq/analytics/overview", headers: bearer_headers(@token)
    distribution = JSON.parse(response.body).dig("overview", "realme_distribution")

    assert_equal 1, distribution.fetch("full_badge")
    assert_equal 1, distribution.fetch("messaging_eligible")
    assert_equal 1, distribution.fetch("pending")

    # Sanity: every counted profile lands in exactly one bucket.
    assert_equal 3, distribution.values.sum
    [ badge_profile, eligible_profile, pending_profile ].each { |p| assert p.persisted? }
  end

  test "requires analytics capability" do
    role = AdminRole.create!(name: "trust_safety")
    @admin.admin_assignments.first.update!(admin_role: role)

    get "/api/v1/hq/analytics/overview", headers: bearer_headers(@token)
    assert_response :forbidden
  end

  private

  def create_verified_profile(check_types_approved: [], check_types_pending: [], email_verified: false)
    user = User.create!
    BrandMembership.create!(brand: @brand, user:)
    profile = Profile.create!(
      brand: @brand, user:, brand_membership: user.brand_memberships.last,
      display_name: "M", birthdate: 30.years.ago.to_date, gender: "man", status: :active, visibility: :visible
    )
    user.identity_identifiers.create!(brand: @brand, kind: :email, normalized_value: "#{SecureRandom.hex(6)}@example.com", verified_at: email_verified ? Time.current : nil)
    check_types_approved.each do |check_type|
      VerificationAssertion.create!(brand: @brand, user:, check_type:, status: "approved", source_type: "test", source_id: SecureRandom.hex(8))
    end
    check_types_pending.each do |check_type|
      VerificationAssertion.create!(brand: @brand, user:, check_type:, status: "pending", source_type: "test", source_id: SecureRandom.hex(8))
    end
    profile
  end

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
