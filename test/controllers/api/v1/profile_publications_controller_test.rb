require "test_helper"

class Api::V1::ProfilePublicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(brand: @brand, user: @user, brand_membership: @membership)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "requires authentication" do
    post "/api/v1/profile/publication"

    assert_response :unauthorized
  end

  test "rejects activation with structured missing requirements" do
    post "/api/v1/profile/publication", headers: bearer_headers(@token)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "profile_incomplete", payload.fetch("error")
    assert_includes payload.fetch("completion").fetch("missing"), "display_name"
    assert @profile.reload.draft?
    assert @profile.hidden?
  end

  test "activates and publishes a complete profile" do
    complete_profile

    post "/api/v1/profile/publication", headers: bearer_headers(@token)

    assert_response :success
    assert @profile.reload.active?
    assert @profile.visible?
    payload = JSON.parse(response.body).fetch("profile")
    assert_equal "active", payload.fetch("status")
    assert_equal "visible", payload.fetch("visibility")
  end

  test "deactivates and hides a published profile idempotently" do
    complete_profile
    @profile.update!(status: :active, visibility: :visible)

    2.times do
      delete "/api/v1/profile/publication", headers: bearer_headers(@token)
      assert_response :success
    end

    assert @profile.reload.draft?
    assert @profile.hidden?
  end

  test "removing required data automatically unpublishes an active profile" do
    complete_profile
    @profile.update!(status: :active, visibility: :visible)

    patch "/api/v1/profile", headers: bearer_headers(@token), params: { display_name: "" }

    assert_response :success
    assert @profile.reload.draft?
    assert @profile.hidden?
  end

  test "removing required preferences automatically unpublishes an active profile" do
    complete_profile
    @profile.update!(status: :active, visibility: :visible)

    patch "/api/v1/profile/preferences", headers: bearer_headers(@token), params: { interested_in: [] }

    assert_response :success
    assert @profile.reload.draft?
    assert @profile.hidden?
  end

  test "deleting the required photo automatically unpublishes an active profile" do
    photo = complete_profile
    @profile.update!(status: :active, visibility: :visible)

    delete "/api/v1/profile/photos/#{photo.id}", headers: bearer_headers(@token)

    assert_response :success
    assert @profile.reload.draft?
    assert @profile.hidden?
  end

  test "removing a required option automatically unpublishes an active profile" do
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    @brand.update!(profile_requirements: {
      profile_fields: [], preference_fields: [], collections: [], option_groups: %w[ intents vibes ]
    })
    Profiles::OptionSelections.replace!(
      profile: @profile,
      selections: { intents: [ "hookups" ], vibes: [ "chill" ] }
    )
    @profile.update!(status: :active, visibility: :visible)

    patch "/api/v1/profile/options",
      headers: bearer_headers(@token),
      params: { selections: { intents: [] } },
      as: :json

    assert_response :success
    assert @profile.reload.draft?
    assert @profile.hidden?
  end

  test "DateZA rejects activation without a location and activates once one is added" do
    dateza, token, profile = complete_dateza_profile

    post "/api/v1/profile/publication", headers: bearer_headers(token)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_equal "profile_incomplete", payload.fetch("error")
    assert_includes payload.fetch("completion").fetch("missing"), "location"

    ProfileLocation.create!(
      brand: dateza, user: profile.user, profile:, latitude: -26.2041, longitude: 28.0473,
      accuracy_meters: 25, source: "device", captured_at: Time.current
    )

    post "/api/v1/profile/publication", headers: bearer_headers(token)

    assert_response :success
    assert profile.reload.active?
  end

  test "DateZA unpublishes an active profile when its location is removed" do
    dateza, token, profile = complete_dateza_profile
    ProfileLocation.create!(
      brand: dateza, user: profile.user, profile:, latitude: -26.2041, longitude: 28.0473,
      accuracy_meters: 25, source: "device", captured_at: Time.current
    )
    post "/api/v1/profile/publication", headers: bearer_headers(token)
    assert_response :success
    assert profile.reload.active?

    delete "/api/v1/profile/location", headers: bearer_headers(token)

    assert_response :success
    assert profile.reload.draft?
    assert profile.hidden?
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def complete_dateza_profile
    dateza = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: dateza)
    BrandDomain.create!(brand: dateza, host: "dateza.test")
    user = User.create!(first_name: "Thandi", last_name: "Mokoena")
    membership = BrandMembership.create!(brand: dateza, user:)
    token, = Session.issue!(brand: dateza, user:)
    host! "dateza.test"

    profile = Profile.create!(
      brand: dateza, user:, brand_membership: membership, display_name: "Thandi",
      birthdate: 28.years.ago.to_date, gender: "woman", country_code: "ZA", city: "Johannesburg",
      bio: "Hello there.", smoking: "never", drinking: "never"
    )
    ProfilePreference.create!(
      brand: dateza, user:, profile:, min_age: 25, max_age: 40, interested_in: [ "man" ], max_distance_km: 50
    )
    Profiles::OptionSelections.replace!(
      profile:,
      selections: {
        relationship_intent: [ "long_term_relationship" ], has_children: [ "no" ], wants_children: [ "yes" ],
        religion_importance: [ "not_important" ], social_style: [ "introverted" ], meeting_pace: [ "meet_soon" ]
      }
    )
    photo = ProfilePhoto.new(brand: dateza, user:, profile:)
    photo.image.attach(
      io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
      filename: "profile_photo.png",
      content_type: "image/png"
    )
    photo.save!

    [ dateza, token, profile ]
  end

  def complete_profile
    @profile.update!(display_name: "Ada", birthdate: 30.years.ago.to_date, gender: "woman")
    ProfilePreference.create!(
      brand: @brand, user: @user, profile: @profile,
      min_age: 25, max_age: 40, interested_in: [ "man" ]
    ) unless ProfilePreference.kept.exists?(profile: @profile)
    photo = ProfilePhoto.new(brand: @brand, user: @user, profile: @profile)
    photo.image.attach(
      io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
      filename: "profile_photo.png",
      content_type: "image/png"
    )
    photo.save!
    photo
  end
end
