require "test_helper"

class Api::V1::ProfileControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "requires authentication" do
    get "/api/v1/profile"

    assert_response :unauthorized
  end

  test "shows null profile when current user has not created one" do
    get "/api/v1/profile", headers: bearer_headers(@token)

    assert_response :success
    assert_equal({ "profile" => nil }, JSON.parse(response.body))
  end

  test "creates the current user's brand profile" do
    assert_difference -> { Profile.count }, 1 do
      patch "/api/v1/profile",
        headers: bearer_headers(@token),
        params: {
          display_name: "Ada",
          bio: "Building something real.",
          birthdate: "1994-05-01",
          gender: "woman",
          country_code: "za",
          city: "Johannesburg",
          occupation: "Engineer",
          height_cm: 170,
          languages_spoken: %w[ English Zulu ],
          smoking: "never",
          drinking: "occasionally",
          fitness: "regularly",
          visibility: "visible"
        }
    end

    assert_response :success
    response_body = JSON.parse(response.body)
    profile = Profile.last

    assert_equal @brand, profile.brand
    assert_equal @user, profile.user
    assert_equal @membership, profile.brand_membership
    assert_equal profile.public_id, response_body.fetch("profile").fetch("id")
    assert_not_equal profile.id.to_s, response_body.fetch("profile").fetch("id")
    assert_equal "Ada", response_body.fetch("profile").fetch("display_name")
    assert_equal "hookus", response_body.fetch("profile").fetch("brand").fetch("slug")
    assert_equal "visible", response_body.fetch("profile").fetch("visibility")
    assert_equal "ZA", response_body.fetch("profile").fetch("country_code")
    assert_equal %w[ English Zulu ], response_body.fetch("profile").fetch("languages_spoken")
    assert_equal false, response_body.fetch("profile").fetch("completion").fetch("complete")
    assert_includes response_body.fetch("profile").fetch("completion").fetch("missing"), "preferences.min_age"
  end

  test "returns complete profile completion when required profile and preferences exist" do
    profile = Profile.create!(
      user: @user,
      brand: @brand,
      brand_membership: @membership,
      display_name: "Ada",
      birthdate: 25.years.ago.to_date,
      gender: "woman"
    )
    ProfilePreference.create!(
      profile:,
      user: @user,
      brand: @brand,
      min_age: 25,
      max_age: 35,
      interested_in: [ "man" ]
    )
    photo = ProfilePhoto.new(profile:, user: @user, brand: @brand)
    photo.image.attach(
      io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
      filename: "profile_photo.png",
      content_type: "image/png"
    )
    photo.save!

    get "/api/v1/profile", headers: bearer_headers(@token)

    assert_response :success
    completion = JSON.parse(response.body).fetch("profile").fetch("completion")
    assert_equal true, completion.fetch("complete")
    assert_equal 100, completion.fetch("percent")
    assert_empty completion.fetch("missing")
  end

  test "updates existing current brand profile" do
    profile = Profile.create!(user: @user, brand: @brand, brand_membership: @membership, display_name: "Ada")

    assert_no_difference -> { Profile.count } do
      patch "/api/v1/profile",
        headers: bearer_headers(@token),
        params: { display_name: "Ada Updated", bio: "Updated bio" }
    end

    assert_response :success
    profile.reload
    assert_equal "Ada Updated", profile.display_name
    assert_equal "Updated bio", profile.bio
  end

  test "does not show another brand profile for the same user" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other_membership = BrandMembership.create!(brand: other_brand, user: @user)
    Profile.create!(
      user: @user,
      brand: other_brand,
      brand_membership: other_membership,
      display_name: "Date9ja Ada"
    )

    get "/api/v1/profile", headers: bearer_headers(@token)

    assert_response :success
    assert_equal({ "profile" => nil }, JSON.parse(response.body))
  end

  test "rejects invalid profile values" do
    patch "/api/v1/profile",
      headers: bearer_headers(@token),
      params: { display_name: "A" * 81 }

    assert_response :unprocessable_entity
    assert_equal "invalid_profile", JSON.parse(response.body).fetch("error")
  end

  test "rejects underage profile birthdates" do
    patch "/api/v1/profile",
      headers: bearer_headers(@token),
      params: { birthdate: 17.years.ago.to_date.iso8601 }

    assert_response :unprocessable_entity
    response_body = JSON.parse(response.body)
    assert_equal "invalid_profile", response_body.fetch("error")
    assert_includes response_body.fetch("details").fetch("birthdate"), "must be at least 18 years ago"
  end

  test "does not allow users to update lifecycle status directly" do
    patch "/api/v1/profile",
      headers: bearer_headers(@token),
      params: { display_name: "Ada", status: "active" }

    assert_response :success
    assert Profile.last.draft?
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
