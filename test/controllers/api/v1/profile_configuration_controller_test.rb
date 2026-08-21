require "test_helper"

class Api::V1::ProfileConfigurationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    BrandMembership.create!(brand: @brand, user: @user)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "requires authentication" do
    get "/api/v1/profile/configuration"

    assert_response :unauthorized
  end

  test "returns the current brand profile contract" do
    @brand.profile_options.find_by!(code: "raves").update!(status: :retired)
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    other_group = ProfileOptionGroup.create!(brand: other_brand, key: "faith", label: "Faith")
    ProfileOption.create!(brand: other_brand, profile_option_group: other_group, code: "christian", label: "Christian")

    get "/api/v1/profile/configuration", headers: bearer_headers(@token)

    assert_response :success
    configuration = JSON.parse(response.body).fetch("configuration")
    onboarding = JSON.parse(response.body).fetch("onboarding")
    assert configuration.fetch("profile_fields").find { |field| field.fetch("key") == "bio" }.fetch("required")
    groups = configuration.fetch("option_groups").index_by { |group| group.fetch("key") }
    assert groups.fetch("intents").fetch("required")
    assert groups.fetch("vibes").fetch("required")
    assert_not_includes groups.fetch("vibes").fetch("options").pluck("code"), "raves"
    assert_not groups.key?("faith")
    assert_equal "profile_required", onboarding.fetch("state")
    assert_equal "profile", onboarding.fetch("next_step")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
