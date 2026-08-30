require "test_helper"

class Api::V1::Hq::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @ada = create_profile(brand: @brand, display_name: "Ada")
    IdentityIdentifier.create!(user: @ada.user, kind: :email, normalized_value: "ada@example.com")
    @admin, @admin_token = create_admin(brand: @brand)
    host! "hookus.test"
  end

  # --- authorization -----------------------------------------------------

  test "unauthenticated requests are rejected" do
    get "/api/v1/hq/members/ada@example.com"
    assert_response :unauthorized

    get "/api/v1/hq/members/ada@example.com/security_events"
    assert_response :unauthorized
  end

  test "an ordinary authenticated user cannot reach HQ" do
    user_token, = Session.issue!(brand: @brand, user: @ada.user)

    get "/api/v1/hq/members/ada@example.com", headers: bearer_headers(user_token)
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body).fetch("error")
  end

  test "an admin assigned to another brand cannot look up this brand's members" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    _admin, token = create_admin(brand: @brand, assign_brand: other_brand)

    get "/api/v1/hq/members/ada@example.com", headers: bearer_headers(token)
    assert_response :forbidden
  end

  # --- tenant isolation ----------------------------------------------------

  test "a member who only exists on another brand is not found here" do
    other_brand = Brand.create!(slug: "other", name: "Other")
    other_member = create_profile(brand: other_brand, display_name: "Cross")
    IdentityIdentifier.create!(user: other_member.user, kind: :email, normalized_value: "cross@example.com")

    get "/api/v1/hq/members/cross@example.com", headers: bearer_headers(@admin_token)
    assert_response :not_found
    assert_equal "member_unavailable", JSON.parse(response.body).fetch("error")

    get "/api/v1/hq/members/#{other_member.public_id}", headers: bearer_headers(@admin_token)
    assert_response :not_found
  end

  # --- lookup ----------------------------------------------------------------

  test "an unknown lookup value is not found" do
    get "/api/v1/hq/members/nobody@example.com", headers: bearer_headers(@admin_token)
    assert_response :not_found
    assert_equal "member_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "email lookup is case-insensitive" do
    get "/api/v1/hq/members/ADA@Example.com", headers: bearer_headers(@admin_token)
    assert_response :success
    assert_equal @ada.user_id, JSON.parse(response.body).dig("member", "user_id")
  end

  test "lookup by profile public_id works" do
    get "/api/v1/hq/members/#{@ada.public_id}", headers: bearer_headers(@admin_token)
    assert_response :success
    assert_equal @ada.public_id, JSON.parse(response.body).dig("sections", "profile", "public_id")
  end

  test "member directory is brand-scoped, paginated, and audited" do
    sam = create_profile(brand: @brand, display_name: "Sam")
    other_brand = Brand.create!(slug: "other", name: "Other")
    create_profile(brand: other_brand, display_name: "Hidden")

    assert_difference -> { SecurityEvent.where(event_type: "hq.member_directory_viewed").count }, 1 do
      get "/api/v1/hq/members", headers: bearer_headers(@admin_token), params: { limit: 1 }
    end
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body.fetch("members").size
    assert body.fetch("next_cursor").present?
    assert_equal sam.public_id, body.fetch("members").first.fetch("profile_id")
    assert_not_includes body.to_s, "ada@example.com"

    get "/api/v1/hq/members", headers: bearer_headers(@admin_token), params: { limit: 1, cursor: body.fetch("next_cursor") }
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("members").size
    assert JSON.parse(response.body).fetch("members").first.key?("user_id")
  end

  test "member directory rejects invalid filters and does not expose another brand" do
    create_profile(brand: @brand, display_name: "Sam")
    other_brand = Brand.create!(slug: "other", name: "Other")
    create_profile(brand: other_brand, display_name: "Hidden")

    get "/api/v1/hq/members", headers: bearer_headers(@admin_token), params: { status: "unknown" }
    assert_response :unprocessable_entity
    assert_equal "invalid_filter", JSON.parse(response.body).fetch("error")

    get "/api/v1/hq/members", headers: bearer_headers(@admin_token), params: { limit: 0 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")

    get "/api/v1/hq/members", headers: bearer_headers(@admin_token), params: { limit: 100 }
    assert_response :success
    members = JSON.parse(response.body).fetch("members")
    assert_includes members.filter_map { |member| member["display_name"] }, "Ada"
    assert_includes members.filter_map { |member| member["display_name"] }, "Sam"
    assert_not_includes members.filter_map { |member| member["display_name"] }, "Hidden"
  end

  # --- member 360 payload + audit -------------------------------------------

  test "member 360 returns all six sections and audits the read without leaking credentials" do
    assert_difference -> { SecurityEvent.where(event_type: "hq.member_360_viewed").count }, 1 do
      get "/api/v1/hq/members/ada@example.com", headers: bearer_headers(@admin_token)
    end
    assert_response :success

    body = JSON.parse(response.body)
    sections = body.fetch("sections")
    assert_equal %w[identity profile product comms safety activity], sections.keys

    flat = body.to_s
    %w[password credential token_digest].each do |leak|
      assert_not_includes flat, leak, "member 360 leaked #{leak}"
    end

    event = SecurityEvent.where(event_type: "hq.member_360_viewed").last
    assert_equal @admin.id, event.metadata.fetch("admin_user_id")
    assert_equal @ada.user_id, event.metadata.fetch("target_user_id")
  end

  test "a member with no profile yet renders empty-state sections instead of crashing" do
    bare_user = User.create!
    BrandMembership.create!(brand: @brand, user: bare_user)
    IdentityIdentifier.create!(user: bare_user, kind: :email, normalized_value: "bare@example.com")

    get "/api/v1/hq/members/bare@example.com", headers: bearer_headers(@admin_token)
    assert_response :success
    assert_equal false, JSON.parse(response.body).dig("sections", "profile", "exists")
  end

  # --- security_events / auth_attempts / enforcements sub-resources ---------

  test "security_events is paginated, brand-scoped, and audited" do
    SecurityEvent.create!(brand: @brand, user: @ada.user, event_type: "identity.password_changed", severity: :info)
    other_brand = Brand.create!(slug: "other", name: "Other")
    SecurityEvent.create!(brand: other_brand, user: @ada.user, event_type: "identity.password_changed", severity: :info)

    assert_difference -> { SecurityEvent.where(event_type: "hq.member_security_events_viewed").count }, 1 do
      get "/api/v1/hq/members/ada@example.com/security_events", headers: bearer_headers(@admin_token)
    end
    assert_response :success

    events = JSON.parse(response.body).fetch("security_events")
    assert_equal 1, events.size
    assert_equal "identity.password_changed", events.first.fetch("event_type")
  end

  test "auth_attempts pagination has no duplicates across pages" do
    3.times do |i|
      attempt = AuthAttempt.create!(
        brand: @brand, user: @ada.user, kind: :password, result: :succeeded, identifier: "ada@example.com"
      )
      attempt.update_columns(created_at: Time.utc(2026, 8, 17, 9 + i, 0, 0))
    end

    get "/api/v1/hq/members/ada@example.com/auth_attempts",
      headers: bearer_headers(@admin_token), params: { limit: 2 }
    first_page = JSON.parse(response.body)
    assert_equal 2, first_page.fetch("auth_attempts").size
    assert first_page.fetch("next_cursor").present?

    get "/api/v1/hq/members/ada@example.com/auth_attempts",
      headers: bearer_headers(@admin_token), params: { limit: 2, cursor: first_page.fetch("next_cursor") }
    second_page = JSON.parse(response.body)
    assert_equal 1, second_page.fetch("auth_attempts").size
    assert_nil second_page.fetch("next_cursor")
  end

  test "an invalid limit or cursor is rejected" do
    get "/api/v1/hq/members/ada@example.com/security_events",
      headers: bearer_headers(@admin_token), params: { limit: 0 }
    assert_response :unprocessable_entity
    assert_equal "invalid_limit", JSON.parse(response.body).fetch("error")

    get "/api/v1/hq/members/ada@example.com/security_events",
      headers: bearer_headers(@admin_token), params: { cursor: "garbage" }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")
  end

  test "a cursor cannot be replayed against a different member" do
    other = create_profile(brand: @brand, display_name: "Sam")
    IdentityIdentifier.create!(user: other.user, kind: :email, normalized_value: "sam@example.com")
    3.times { SecurityEvent.create!(brand: @brand, user: @ada.user, event_type: "x", severity: :info) }

    get "/api/v1/hq/members/ada@example.com/security_events",
      headers: bearer_headers(@admin_token), params: { limit: 1 }
    cursor = JSON.parse(response.body).fetch("next_cursor")

    get "/api/v1/hq/members/sam@example.com/security_events",
      headers: bearer_headers(@admin_token), params: { limit: 1, cursor: }
    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", JSON.parse(response.body).fetch("error")
  end

  test "enforcements sub-resource lists this member's enforcement history" do
    AccountEnforcement.create!(
      brand: @brand, user: @ada.user, brand_membership: @ada.brand_membership, profile: @ada,
      admin_user: @admin, reason: "test"
    )

    get "/api/v1/hq/members/ada@example.com/enforcements", headers: bearer_headers(@admin_token)
    assert_response :success
    enforcements = JSON.parse(response.body).fetch("enforcements")
    assert_equal 1, enforcements.size
    assert_equal "active", enforcements.first.fetch("state")
  end

  # --- discovery_diagnostic ---------------------------------------------

  test "discovery_diagnostic reports ineligibility without erroring for an incomplete profile" do
    assert_difference -> { SecurityEvent.where(event_type: "hq.member_discovery_diagnostic_viewed").count }, 1 do
      get "/api/v1/hq/members/ada@example.com/discovery_diagnostic", headers: bearer_headers(@admin_token)
    end
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal false, body.fetch("eligible")
    assert_equal "profile_unavailable", body.fetch("ineligibility_reason")
    assert_equal [], body.fetch("stages")
  end

  test "discovery_diagnostic returns a stage breakdown for a fully eligible member" do
    ProfilePreference.create!(
      brand: @brand, user: @ada.user, profile: @ada, interested_in: [ "person" ], min_age: 18, max_age: 99
    )

    get "/api/v1/hq/members/ada@example.com/discovery_diagnostic", headers: bearer_headers(@admin_token)
    assert_response :success

    body = JSON.parse(response.body)
    assert body.fetch("eligible")
    assert_nil body.fetch("ineligibility_reason")
    assert_equal %w[visible_active_profiles reciprocal_gender_age_distance final_eligible_candidates],
      body.fetch("stages").pluck("stage")
  end

  test "discovery_diagnostic on a member without a profile is not found" do
    bare_user = User.create!
    BrandMembership.create!(brand: @brand, user: bare_user)
    IdentityIdentifier.create!(user: bare_user, kind: :email, normalized_value: "bare@example.com")

    get "/api/v1/hq/members/bare@example.com/discovery_diagnostic", headers: bearer_headers(@admin_token)
    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand:, display_name:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(
      brand:, user:, brand_membership: membership, display_name:,
      birthdate: 28.years.ago.to_date, gender: "person", status: :active, visibility: :visible
    )
  end

  def create_admin(brand:, assign_brand: nil, role_name: "moderator")
    user = User.create!
    BrandMembership.create!(brand:, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: role_name)
    AdminAssignment.create!(admin_user:, brand: assign_brand || brand, admin_role: role, status: :active)
    token = issue_mfa_verified_admin_session!(user:, brand:, admin_user:)
    [ admin_user, token ]
  end
end
