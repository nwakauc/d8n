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
    body = JSON.parse(response.body)
    assert_nil body.fetch("profile")
    assert_equal "profile_required", body.fetch("onboarding").fetch("state")
    assert_equal "profile", body.fetch("onboarding").fetch("next_step")
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
    assert_equal "profile_incomplete", response_body.fetch("onboarding").fetch("state")
    assert_equal "preferences", response_body.fetch("onboarding").fetch("next_step")
  end

  test "DateZA onboarding persists private identity names and derives only the initial display name" do
    dateza = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: dateza)
    BrandDomain.create!(brand: dateza, host: "dateza.test")
    BrandMembership.create!(brand: dateza, user: @user)
    token, = Session.issue!(brand: dateza, user: @user)
    host! "dateza.test"

    patch "/api/v1/profile",
      headers: bearer_headers(token),
      params: {
        first_name: " Thandi ", last_name: " Mokoena ", birthdate: "1994-05-01",
        gender: "woman", country_code: "ZA", city: "Johannesburg"
      }

    assert_response :success
    profile = Profile.kept.find_by!(brand: dateza, user: @user)
    body = JSON.parse(response.body).fetch("profile")
    assert_equal "Thandi", @user.reload.first_name
    assert_equal "Mokoena", @user.last_name
    assert_equal "Thandi", profile.display_name
    assert_equal "Thandi", body.fetch("first_name")
    assert_equal "Mokoena", body.fetch("last_name")
    assert_equal "Thandi", body.fetch("display_name")
  end

  test "another brand owner response does not expose platform identity names" do
    @user.update!(first_name: "Thandi", last_name: "Mokoena")
    Profile.create!(user: @user, brand: @brand, brand_membership: @membership, display_name: "T")

    get "/api/v1/profile", headers: bearer_headers(@token)

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert_not profile.key?("first_name")
    assert_not profile.key?("last_name")
  end

  test "DateZA rejects configured platform fields that the brand has not enabled" do
    dateza, token = install_dateza_for_current_user

    assert_no_difference -> { Profile.where(brand: dateza, user: @user).count } do
      patch "/api/v1/profile",
        headers: bearer_headers(token),
        params: { display_name: "Thandi", pronouns: "she/her", body_type: "athletic" }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "invalid_profile_fields", body.fetch("error")
    assert_equal %w[ body_type pronouns ], body.dig("details", "fields")
  end

  test "DateZA accepts enabled optional fields and ignores unknown input" do
    _dateza, token = install_dateza_for_current_user

    patch "/api/v1/profile",
      headers: bearer_headers(token),
      params: {
        display_name: "Thandi", job_title: "Engineer",
        languages: [ { code: "en", proficiency: "fluent", primary: true } ],
        future_client_hint: "ignored"
      }

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert_equal "Engineer", profile.fetch("job_title")
    assert_equal "en", profile.fetch("languages").first.fetch("code")
    assert_not profile.key?("future_client_hint")
  end

  test "DateZA owner response exposes enabled rich fields and omits disabled historical fields" do
    dateza, token = install_dateza_for_current_user
    membership = BrandMembership.find_by!(brand: dateza, user: @user)
    profile = Profile.create!(
      brand: dateza, user: @user, brand_membership: membership,
      display_name: "Thandi", birthdate: 30.years.ago.to_date,
      pronouns: "she/her", body_type: "athletic", company_name: "Private Corp",
      languages_spoken: [ "English" ], job_title: "Engineer"
    )

    get "/api/v1/profile", headers: bearer_headers(token)

    assert_response :success
    payload = JSON.parse(response.body).fetch("profile")
    assert_equal profile.birthdate.iso8601, payload.fetch("birthdate")
    assert_equal "Engineer", payload.fetch("job_title")
    assert_equal "Private Corp", payload.fetch("company_name")
    assert payload.key?("publication_completion")
    assert payload.key?("profile_completion")
    assert_equal({ "photos" => 0, "prompts" => 0, "interests" => 0 }, payload.fetch("counts"))
    assert_equal false, payload.dig("verification", "contact", "verified")
    %w[pronouns body_type languages_spoken].each do |field|
      assert_not payload.key?(field), "expected disabled #{field} to be omitted"
    end
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

  test "reports location as unconfigured with no ProfileLocation and configured once one exists" do
    profile = Profile.create!(user: @user, brand: @brand, brand_membership: @membership, display_name: "Ada")

    get "/api/v1/profile", headers: bearer_headers(@token)
    assert_response :success
    assert_equal false, JSON.parse(response.body).fetch("profile").fetch("location").fetch("configured")

    ProfileLocation.create!(
      profile:, user: @user, brand: @brand, latitude: -26.2041, longitude: 28.0473,
      accuracy_meters: 25, source: "device", captured_at: Time.current
    )

    get "/api/v1/profile", headers: bearer_headers(@token)
    assert_response :success
    assert_equal true, JSON.parse(response.body).fetch("profile").fetch("location").fetch("configured")
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
    body = JSON.parse(response.body)
    assert_nil body.fetch("profile")
    assert_equal "profile_required", body.fetch("onboarding").fetch("state")
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

  test "accepts the new optional identity and structured language fields" do
    patch "/api/v1/profile",
      headers: bearer_headers(@token),
      params: {
        display_name: "Ada", pronouns: "she/her", job_title: "Engineer",
        company_name: "D8N", school_or_institution: "UCT",
        looking_for_text: "Someone curious.", children_count: 1,
        languages: [ { code: "en", proficiency: "fluent", primary: true }, { code: "zu" } ]
      }

    assert_response :success
    profile = JSON.parse(response.body).fetch("profile")
    assert_equal "she/her", profile.fetch("pronouns")
    assert_equal "Engineer", profile.fetch("job_title")
    assert_equal "D8N", profile.fetch("company_name")
    assert_equal 1, profile.fetch("children_count")
    assert_equal %w[ en zu ], profile.fetch("languages").map { |l| l.fetch("code") }
    assert_equal "English", profile.fetch("languages").first.fetch("label")
  end

  test "rejects invalid structured languages" do
    patch "/api/v1/profile",
      headers: bearer_headers(@token),
      params: { languages: [ { code: "en", primary: true }, { code: "zu", primary: true } ] }

    assert_response :unprocessable_entity
    assert_equal "invalid_profile", JSON.parse(response.body).fetch("error")
  end

  test "partial update of one field does not erase unrelated fields" do
    patch "/api/v1/profile", headers: bearer_headers(@token),
      params: { display_name: "Ada", job_title: "Engineer", pronouns: "she/her" }
    assert_response :success

    patch "/api/v1/profile", headers: bearer_headers(@token), params: { bio: "Just a bio." }
    assert_response :success

    profile = Profile.last
    assert_equal "Just a bio.", profile.bio
    assert_equal "Engineer", profile.job_title
    assert_equal "she/her", profile.pronouns
  end

  private

  def install_dateza_for_current_user
    dateza = Brand.create!(slug: "dateza", name: "DateZA")
    Profiles::DatezaProfileCatalog.install!(brand: dateza)
    BrandDomain.create!(brand: dateza, host: "dateza.test")
    BrandMembership.find_or_create_by!(brand: dateza, user: @user)
    token, = Session.issue!(brand: dateza, user: @user)
    host! "dateza.test"
    [ dateza, token ]
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
