require "test_helper"

class Api::V1::Admin::IdentityCorrectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: @brand, host: "date9ja.test")
    @profile = create_profile(brand: @brand, gender: "man")
    @admin, @token = create_admin(brand: @brand, role_name: "trust_safety")
    host! "date9ja.test"
  end

  test "requires the identity_correction capability" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/identity_corrections",
      params: { field: "gender", value: "woman", reason: "member requested correction" }
    assert_response :unauthorized

    ordinary_token, = Session.issue!(brand: @brand, user: @profile.user)
    post "/api/v1/admin/profiles/#{@profile.public_id}/identity_corrections",
      headers: bearer_headers(ordinary_token), params: { field: "gender", value: "woman", reason: "x" }
    assert_response :forbidden
  end

  test "requires MFA" do
    user = User.create!
    BrandMembership.create!(brand: @brand, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: "trust_safety")
    AdminAssignment.create!(admin_user:, brand: @brand, admin_role: role, status: :active)
    token, = Session.issue!(brand: @brand, user:)

    post "/api/v1/admin/profiles/#{@profile.public_id}/identity_corrections",
      headers: bearer_headers(token), params: { field: "gender", value: "woman", reason: "x" }
    assert_response :forbidden
    assert_equal "admin_mfa_required", JSON.parse(response.body).fetch("error")
  end

  test "man -> woman gender correction updates the canonical value, records history, and is audited" do
    assert_difference -> { SecurityEvent.where(event_type: "admin.identity_corrected").count }, 1 do
      post "/api/v1/admin/profiles/#{@profile.public_id}/identity_corrections",
        headers: bearer_headers(@token), params: { field: "gender", value: "woman", reason: "member requested correction" }
    end
    assert_response :created
    body = JSON.parse(response.body).fetch("correction")
    assert_equal "gender", body.fetch("field")
    assert_equal "man", body.fetch("previous_value")
    assert_equal "woman", body.fetch("new_value")

    assert_equal "woman", @profile.reload.gender

    event = SecurityEvent.where(event_type: "admin.identity_corrected").last
    assert_not_includes event.metadata.to_s, "member requested correction"

    get "/api/v1/admin/profiles/#{@profile.public_id}/identity_corrections", headers: bearer_headers(@token)
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("identity_corrections").size
  end

  test "woman -> man gender correction where valid" do
    @profile.update!(gender: "woman")

    post "/api/v1/admin/profiles/#{@profile.public_id}/identity_corrections",
      headers: bearer_headers(@token), params: { field: "gender", value: "man", reason: "correction" }
    assert_response :created
    assert_equal "man", @profile.reload.gender
  end

  test "looking_for (interested_in) correction updates the canonical preference" do
    preference = ProfilePreference.create!(brand: @brand, profile: @profile, user: @profile.user, interested_in: %w[man], min_age: 18, max_age: 60)

    post "/api/v1/admin/profiles/#{@profile.public_id}/identity_corrections",
      headers: bearer_headers(@token), params: { field: "interested_in", value: [ "woman" ], reason: "correction" }
    assert_response :created
    body = JSON.parse(response.body).fetch("correction")
    assert_equal [ "man" ], body.fetch("previous_value")
    assert_equal [ "woman" ], body.fetch("new_value")

    assert_equal [ "woman" ], preference.reload.interested_in
  end

  test "rejects an unknown field" do
    post "/api/v1/admin/profiles/#{@profile.public_id}/identity_corrections",
      headers: bearer_headers(@token), params: { field: "email", value: "x", reason: "x" }
    assert_response :unprocessable_entity
    assert_equal "invalid_field", JSON.parse(response.body).fetch("error")
  end

  test "rejects an invalid interested_in value" do
    ProfilePreference.create!(brand: @brand, profile: @profile, user: @profile.user, interested_in: %w[man], min_age: 18, max_age: 60)

    post "/api/v1/admin/profiles/#{@profile.public_id}/identity_corrections",
      headers: bearer_headers(@token), params: { field: "interested_in", value: [ "x" * 41 ], reason: "x" }
    assert_response :unprocessable_entity
    assert_equal "invalid_value", JSON.parse(response.body).fetch("error")
  end

  test "a cross-brand target is not disclosed" do
    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    foreign = create_profile(brand: other_brand, gender: "man")

    post "/api/v1/admin/profiles/#{foreign.public_id}/identity_corrections",
      headers: bearer_headers(@token), params: { field: "gender", value: "woman", reason: "x" }
    assert_response :not_found
    assert_equal "profile_unavailable", JSON.parse(response.body).fetch("error")
  end

  test "a correction does not alter an existing match or conversation between the corrected member and another" do
    other = create_profile(brand: @brand, gender: "woman")
    ProfilePreference.create!(brand: @brand, profile: @profile, user: @profile.user, interested_in: %w[woman], min_age: 18, max_age: 60)
    ProfilePreference.create!(brand: @brand, profile: other, user: other.user, interested_in: %w[man], min_age: 18, max_age: 60)
    match = Match.create!(brand: @brand, profile_a: @profile, profile_b: other)

    post "/api/v1/admin/profiles/#{@profile.public_id}/identity_corrections",
      headers: bearer_headers(@token), params: { field: "gender", value: "woman", reason: "correction" }
    assert_response :created

    assert Match.exists?(id: match.id)
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand:, gender: "man")
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership, gender:)
  end

  def create_admin(brand:, role_name: "moderator")
    user = User.create!
    BrandMembership.create!(brand:, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: role_name)
    AdminAssignment.create!(admin_user:, brand:, admin_role: role, status: :active)
    token = issue_mfa_verified_admin_session!(user:, brand:, admin_user:)
    [ admin_user, token ]
  end
end
