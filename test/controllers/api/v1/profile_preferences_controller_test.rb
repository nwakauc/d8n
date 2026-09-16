require "test_helper"

class Api::V1::ProfilePreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(
      brand: @brand,
      user: @user,
      brand_membership: @membership,
      display_name: "Ada",
      birthdate: 25.years.ago.to_date
    )
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "requires authentication" do
    get "/api/v1/profile/preferences"

    assert_response :unauthorized
  end

  test "shows null preferences when none exist" do
    get "/api/v1/profile/preferences", headers: bearer_headers(@token)

    assert_response :success
    assert_equal({ "preferences" => nil }, JSON.parse(response.body))
  end

  test "creates current brand profile preferences" do
    assert_difference -> { ProfilePreference.count }, 1 do
      patch "/api/v1/profile/preferences",
        headers: bearer_headers(@token),
        params: {
          min_age: 25,
          max_age: 35,
          interested_in: [ "woman" ],
          max_distance_km: 50,
          country: "ZA",
          relationship_intent: "relationship"
        }
    end

    assert_response :success
    response_body = JSON.parse(response.body).fetch("preferences")
    preference = ProfilePreference.last

    assert_equal @brand, preference.brand
    assert_equal @user, preference.user
    assert_equal @profile, preference.profile
    assert_equal [ "woman" ], response_body.fetch("interested_in")
    assert_equal "hookus", response_body.fetch("brand").fetch("slug")
    assert_equal @profile.public_id, response_body.fetch("profile_id")
  end

  test "updates existing current brand preferences" do
    preference = ProfilePreference.create!(
      brand: @brand,
      user: @user,
      profile: @profile,
      min_age: 25,
      max_age: 35
    )

    assert_no_difference -> { ProfilePreference.count } do
      patch "/api/v1/profile/preferences",
        headers: bearer_headers(@token),
        params: { min_age: 30, max_age: 45 }
    end

    assert_response :success
    preference.reload
    assert_equal 30, preference.min_age
    assert_equal 45, preference.max_age
  end

  test "requires a current brand profile before preferences can be created" do
    @profile.destroy!

    patch "/api/v1/profile/preferences",
      headers: bearer_headers(@token),
      params: { min_age: 25, max_age: 35 }

    assert_response :forbidden
    assert_equal({ "error" => "profile_required" }, JSON.parse(response.body))
  end

  test "does not show preferences from another brand for the same user" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other_membership = BrandMembership.create!(brand: other_brand, user: @user)
    other_profile = Profile.create!(
      brand: other_brand,
      user: @user,
      brand_membership: other_membership,
      display_name: "Date9ja Ada",
      birthdate: 25.years.ago.to_date
    )
    ProfilePreference.create!(
      brand: other_brand,
      user: @user,
      profile: other_profile,
      min_age: 30,
      max_age: 45
    )

    get "/api/v1/profile/preferences", headers: bearer_headers(@token)

    assert_response :success
    assert_equal({ "preferences" => nil }, JSON.parse(response.body))
  end

  test "rejects invalid preference values" do
    patch "/api/v1/profile/preferences",
      headers: bearer_headers(@token),
      params: { min_age: 17, max_age: 16 }

    assert_response :unprocessable_entity
    response_body = JSON.parse(response.body)
    assert_equal "invalid_preferences", response_body.fetch("error")
    assert response_body.fetch("details").fetch("min_age").present?
  end

  test "a brand with an explicit preference contract rejects and omits unenabled fields" do
    dateza, token, profile = dateza_member

    patch "/api/v1/profile/preferences",
      headers: bearer_headers(token),
      params: { min_age: 25, max_age: 40, interested_in: [ "woman" ], country: "NG", relationship_intent: "marriage" }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "invalid_preference_fields", body.fetch("error")
    assert_equal %w[country relationship_intent], body.fetch("details").fetch("fields")
    assert_not ProfilePreference.exists?(profile:)

    patch "/api/v1/profile/preferences",
      headers: bearer_headers(token),
      params: { min_age: 25, max_age: 40, interested_in: [ "woman" ], max_distance_km: 60 }

    assert_response :success
    preferences = JSON.parse(response.body).fetch("preferences")
    assert_equal %w[brand id interested_in max_age max_distance_km min_age profile_id].sort, preferences.keys.sort
    assert_not preferences.key?("country")
    assert_not preferences.key?("relationship_intent")
    assert_equal "dateza", preferences.fetch("brand").fetch("slug")

    # Persisted value survives reload and is never populated for an unenabled field.
    stored = ProfilePreference.find_by!(profile:)
    assert_equal 60, stored.max_distance_km
    assert_nil stored.country
  end

  private

  def dateza_member
    dateza = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: dateza)
    BrandDomain.create!(brand: dateza, host: "dateza.test")
    user = User.create!
    membership = BrandMembership.create!(brand: dateza, user:)
    profile = Profile.create!(
      brand: dateza, user:, brand_membership: membership,
      display_name: "Zola", birthdate: 27.years.ago.to_date, gender: "woman"
    )
    token, = Session.issue!(brand: dateza, user:)
    host! "dateza.test"
    [ dateza, token, profile ]
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
