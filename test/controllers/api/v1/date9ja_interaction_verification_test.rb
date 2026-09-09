require "test_helper"

# Date9ja market-driven policy (2026-09-09): a member is fully visible the moment
# they finish onboarding — verified email/phone or not — but cannot ACT (view a
# profile, like, pass, hook, message) until the identifier they logged in with is
# verified. Being seen is what pulls them back to verify.
class Api::V1::Date9jaInteractionVerificationTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brands::Date9jaInstaller.call(hosts: [ "date9ja.test" ])
    Geography::NigeriaCatalog.install!

    @viewer = create_date9ja_profile(first_name: "Chidi", gender: "man", interested_in: [ "woman" ])
    @target = create_date9ja_profile(first_name: "Ada", gender: "woman", interested_in: [ "man" ])

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
    assert_includes JSON.parse(response.body).fetch("profiles").pluck("id"), @target.public_id
  end

  test "an unverified member cannot open a profile, like, pass, or message" do
    get "/api/v1/profiles/#{@target.public_id}", headers: bearer_headers(@token)
    assert_verification_required

    assert_no_difference -> { Like.count } do
      post "/api/v1/profiles/#{@target.public_id}/likes", headers: bearer_headers(@token)
    end
    assert_verification_required

    assert_no_difference -> { ProfilePass.count } do
      post "/api/v1/profiles/#{@target.public_id}/pass", headers: bearer_headers(@token)
    end
    assert_verification_required

    get "/api/v1/matches", headers: bearer_headers(@token)
    assert_verification_required
  end

  test "verifying the login identifier unlocks interaction" do
    @viewer_identifier.update!(verified_at: Time.current)

    get "/api/v1/profiles/#{@target.public_id}", headers: bearer_headers(@token)
    assert_response :success

    assert_difference -> { Like.count }, 1 do
      post "/api/v1/profiles/#{@target.public_id}/likes", headers: bearer_headers(@token)
    end
    assert_response :created
  end

  private

  def assert_verification_required
    assert_response :forbidden
    assert_equal({ "error" => "identifier_verification_required" }, JSON.parse(response.body))
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
