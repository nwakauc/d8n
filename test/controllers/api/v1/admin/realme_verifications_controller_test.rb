require "test_helper"

class Api::V1::Admin::RealmeVerificationsControllerTest < ActionDispatch::IntegrationTest
  teardown { ActiveStorage::Blob.all.each { |blob| blob.purge rescue nil } }

  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: @brand, host: "date9ja.test")
    @profile = create_profile(brand: @brand)
    @assertion = create_pending_assertion(user: @profile.user)
    @admin, @token = create_admin(brand: @brand)
    host! "date9ja.test"
  end

  test "requires a brand-assigned moderator" do
    patch "/api/v1/admin/realme_verifications/#{@assertion.id}", params: { status: "approved" }
    assert_response :unauthorized

    ordinary_token, = Session.issue!(brand: @brand, user: @profile.user)
    patch "/api/v1/admin/realme_verifications/#{@assertion.id}",
      headers: bearer_headers(ordinary_token), params: { status: "approved" }
    assert_response :forbidden
  end

  test "index lists only pending member submissions for this brand, oldest first" do
    other_profile = create_profile(brand: @brand)
    approved = create_pending_assertion(user: other_profile.user)
    Trust::ModerateRealmeVerification.call(admin_user: @admin, brand: @brand, assertion_id: approved.id, decision: "approved")

    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    create_pending_assertion(user: create_profile(brand: other_brand).user, brand: other_brand)

    get "/api/v1/admin/realme_verifications", headers: bearer_headers(@token)

    assert_response :success
    ids = JSON.parse(response.body).fetch("assertions").map { |a| a.fetch("id") }
    assert_equal [ @assertion.id ], ids
  end

  test "approves a pending verification" do
    patch "/api/v1/admin/realme_verifications/#{@assertion.id}", headers: bearer_headers(@token),
      params: { status: "approved" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "approved", body.dig("assertion", "status")
    assert_equal true, body.fetch("transitioned")
    assert_equal "approved", @assertion.reload.status
    assert @assertion.reviewed_at.present?
    assert_equal "d8n_admin:#{@admin.id}", @assertion.reviewer_source_id
  end

  test "supports resubmission_requested as a distinct decision from rejected" do
    patch "/api/v1/admin/realme_verifications/#{@assertion.id}", headers: bearer_headers(@token),
      params: { status: "resubmission_requested", note: "blurry photo" }

    assert_response :success
    assert_equal "resubmission_requested", @assertion.reload.status
    assert_equal "blurry photo", @assertion.metadata.fetch("review_note")
  end

  test "rejects an invalid decision" do
    patch "/api/v1/admin/realme_verifications/#{@assertion.id}", headers: bearer_headers(@token),
      params: { status: "maybe" }

    assert_response :unprocessable_entity
    assert_equal "invalid_realme_verification_decision", JSON.parse(response.body).fetch("error")
  end

  test "refuses to re-decide an already-decided assertion" do
    Trust::ModerateRealmeVerification.call(admin_user: @admin, brand: @brand, assertion_id: @assertion.id, decision: "approved")

    patch "/api/v1/admin/realme_verifications/#{@assertion.id}", headers: bearer_headers(@token),
      params: { status: "rejected" }

    assert_response :conflict
    assert_equal "realme_verification_conflict", JSON.parse(response.body).fetch("error")
  end

  test "404s for a foreign brand's or unknown assertion" do
    other_brand = Brand.create!(slug: "hookus", name: "HookUs")
    foreign = create_pending_assertion(user: create_profile(brand: other_brand).user, brand: other_brand)

    [ foreign.id, 0 ].each do |id|
      patch "/api/v1/admin/realme_verifications/#{id}", headers: bearer_headers(@token), params: { status: "approved" }
      assert_response :not_found
      assert_equal "realme_verification_unavailable", JSON.parse(response.body).fetch("error")
    end
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_profile(brand:)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    Profile.create!(brand:, user:, brand_membership: membership)
  end

  def create_pending_assertion(user:, brand: @brand, check_type: "selfie")
    VerificationAssertion.create!(
      brand:, user:, source_type: "member_submission", source_id: SecureRandom.uuid,
      check_type:, status: "pending", submitted_at: Time.current
    )
  end

  def create_admin(brand:)
    user = User.create!
    BrandMembership.create!(brand:, user:)
    admin_user = AdminUser.create!(user:, status: :active)
    role = AdminRole.find_or_create_by!(name: "moderator")
    AdminAssignment.create!(admin_user:, brand:, admin_role: role, status: :active)
    token = issue_mfa_verified_admin_session!(user:, brand:, admin_user:)
    [ admin_user, token ]
  end
end
