require "test_helper"

# Date9ja progressive-verification policy (2026-09-12): contact confirmation is
# never a wall around discovery, profile detail, likes, passes, matching, or chat
# history. Message sending is the higher-trust boundary. An approved non-phone
# RealMe assertion unlocks it; verified email and phone do not.
class Api::V1::Date9jaInteractionVerificationTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brands::Date9jaInstaller.call(hosts: [ "date9ja.test" ])
    Geography::NigeriaCatalog.install!

    @viewer = create_date9ja_profile(first_name: "Chidi", gender: "man", interested_in: [ "woman" ])
    @detail_target = create_date9ja_profile(first_name: "Ada", gender: "woman", interested_in: [ "man" ])
    @like_target = create_date9ja_profile(first_name: "Amara", gender: "woman", interested_in: [ "man" ])
    @pass_target = create_date9ja_profile(first_name: "Ngozi", gender: "woman", interested_in: [ "man" ])
    @matched_target = create_date9ja_profile(first_name: "Ife", gender: "woman", interested_in: [ "man" ])
    profile_a_id, profile_b_id = Match.canonical_pair(@viewer.id, @matched_target.id)
    @match = Match.create!(brand: @brand, profile_a_id:, profile_b_id:)
    @conversation = Messaging::StartConversation.call(
      user: @viewer.user, brand: @brand, match_public_id: @match.public_id
    ).conversation

    @viewer_identifier = IdentityIdentifier.create!(
      user: @viewer.user, kind: :email, normalized_value: "chidi@example.test"
    )
    credential = Credential.create!(
      user: @viewer.user, identity_identifier: @viewer_identifier, kind: :password, status: :active
    )
    @token, = Session.issue!(brand: @brand, user: @viewer.user, credential:)
    host! "date9ja.test"
  end

  test "an unverified member is published, visible, and discoverable without any verification" do
    assert @viewer.reload.active?
    assert @viewer.visible?
    assert_nil @viewer_identifier.verified_at

    get "/api/v1/discovery", headers: bearer_headers(@token)
    assert_response :success
    assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @detail_target.public_id
  end

  test "an unverified member can open profiles like pass match and read conversations" do
    get "/api/v1/profiles/#{@detail_target.public_id}", headers: bearer_headers(@token)
    assert_response :success

    assert_difference -> { Like.count }, 1 do
      post "/api/v1/profiles/#{@like_target.public_id}/likes", headers: bearer_headers(@token)
    end
    assert_response :created

    assert_difference -> { ProfilePass.count }, 1 do
      post "/api/v1/profiles/#{@pass_target.public_id}/pass", headers: bearer_headers(@token)
    end
    assert_response :created

    get "/api/v1/matches", headers: bearer_headers(@token)
    assert_response :success

    get "/api/v1/conversations", headers: bearer_headers(@token)
    assert_response :success

    get "/api/v1/conversations/#{@conversation.public_id}/messages", headers: bearer_headers(@token)
    assert_response :success
  end

  test "an unverified member cannot send a message" do
    assert_no_difference -> { Message.count } do
      post_message("This must not persist")
    end

    assert_realme_required
  end

  test "verifying an email still does not unlock message sending" do
    @viewer_identifier.update!(verified_at: Time.current)

    assert_no_difference -> { Message.count } do
      post_message("Email is not RealMe")
    end

    assert_realme_required
  end

  test "a verified phone does not unlock message sending while Date9ja phone verification is disabled" do
    IdentityIdentifier.create!(
      user: @viewer.user, kind: :phone, normalized_value: "+234 801 234 5678", verified_at: Time.current
    )

    assert_no_difference -> { Message.count } do
      post_message("Phone verification is disabled")
    end

    assert_realme_required
  end

  test "an imported phone assertion does not unlock message sending while Date9ja phone verification is disabled" do
    VerificationAssertion.create!(
      brand: @brand,
      user: @viewer.user,
      source_type: "verification_check",
      source_id: "legacy-phone-1",
      check_type: "phone",
      status: "approved"
    )

    assert_no_difference -> { Message.count } do
      post_message("Imported phone verification is disabled")
    end

    assert_realme_required
  end

  test "Date9ja does not issue phone verification challenges" do
    assert_no_difference -> { OtpChallenge.count } do
      post "/api/v1/auth/verification", headers: bearer_headers(@token), params: { kind: "phone" }
    end

    assert_response :not_found
    assert_equal({ "error" => "capability_not_configured" }, JSON.parse(response.body))
  end

  test "an approved imported RealMe assertion unlocks message sending" do
    VerificationAssertion.create!(
      brand: @brand,
      user: @viewer.user,
      source_type: "verification_check",
      source_id: "legacy-selfie-1",
      check_type: "selfie",
      status: "approved"
    )

    assert_difference -> { Message.count }, 1 do
      post_message("Selfie approved")
    end

    assert_response :created
  end

  test "a live member-submitted selfie, once approved, unlocks sending on the very next request without unlocking the RealMe badge" do
    assert_no_difference -> { Message.count } do
      post_message("Not yet")
    end
    assert_realme_required

    ActiveStorage::Current.url_options = { host: "http://test.local" }
    intent = Identity::RealmeSubmission.create_intent(
      user: @viewer.user, brand: @brand, check_type: "selfie",
      filename: "selfie.jpg", byte_size: 1024,
      checksum: Digest::MD5.base64digest("selfie-bytes"), content_type: "image/jpeg"
    )
    blob = ActiveStorage::Blob.find_signed!(intent.fetch(:signed_id))
    blob.service.upload(blob.key, StringIO.new("\xFF\xD8\xFF".b + ("x" * 1021)))
    assertion = Identity::RealmeSubmission.attach!(user: @viewer.user, brand: @brand, check_type: "selfie", signed_id: intent.fetch(:signed_id))
    assert_equal "pending", assertion.status

    assert_no_difference -> { Message.count } do
      post_message("Still pending review")
    end
    assert_realme_required

    admin_user = AdminUser.create!(user: User.create!, status: :active)
    AdminAssignment.create!(admin_user:, brand: @brand, admin_role: AdminRole.find_or_create_by!(name: "moderator"), status: :active)
    Trust::ModerateRealmeVerification.call(admin_user:, brand: @brand, assertion_id: assertion.id, decision: "approved")

    assert_difference -> { Message.count }, 1 do
      post_message("Approved just now")
    end
    assert_response :created

    get "/api/v1/me", headers: bearer_headers(@token)
    body = JSON.parse(response.body)
    selfie_entry = body.fetch("realme_assertions").find { |e| e.fetch("check_type") == "selfie" }
    assert_equal "approved", selfie_entry.fetch("status")
    assert_equal false, body.fetch("realme_badge"),
      "one approved check unlocks messaging but must not, alone, satisfy the full badge"
  end

  test "another user's verified phone and a rejected assertion do not unlock sending" do
    IdentityIdentifier.create!(
      user: @matched_target.user, kind: :phone, normalized_value: "+234 809 876 5432", verified_at: Time.current
    )
    VerificationAssertion.create!(
      brand: @brand,
      user: @viewer.user,
      source_type: "verification_check",
      source_id: "legacy-video-1",
      check_type: "video",
      status: "rejected"
    )

    assert_no_difference -> { Message.count } do
      post_message("Still blocked")
    end

    assert_realme_required
  end

  private

  def assert_realme_required
    assert_response :forbidden
    assert_equal({ "error" => "realme_verification_required" }, JSON.parse(response.body))
  end

  def post_message(body)
    post "/api/v1/conversations/#{@conversation.public_id}/messages",
      headers: bearer_headers(@token), params: { body: }
  end

  # A migrated Date9ja member: the migration completion contract only needs a
  # given name, adult birthdate, decoded gender, and an orientation — no bio,
  # photo, city, or cultural answer — and publication goes through the normal
  # Profiles::Publication.activate! path.
  def create_date9ja_profile(first_name:, gender:, interested_in:)
    user = User.create!(first_name:)
    membership = BrandMembership.create!(brand: @brand, user:)
    profile = Profile.create!(
      brand: @brand, user:, brand_membership: membership, display_name: first_name,
      gender:, birthdate: 30.years.ago.to_date
    )
    ProfilePreference.create!(brand: @brand, user:, profile:, interested_in:)
    Migration::ReferenceMap.bind!(
      source_system: "date9ja", source_entity: "profile", source_id: "src-#{profile.id}",
      destination: profile, brand: @brand, importer_version: "fixture"
    )
    assert Profiles::Completion.call(profile: profile.reload).complete?,
      "a migrated Date9ja member is complete on the relaxed contract"
    Profiles::Publication.activate!(user:, brand: @brand)
    profile.reload
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
