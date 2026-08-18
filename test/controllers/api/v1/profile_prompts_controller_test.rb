require "test_helper"

class Api::V1::ProfilePromptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    Profiles::HookusProfileCatalog.install!(brand: @brand)
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    membership = BrandMembership.create!(brand: @brand, user: @user)
    @profile = Profile.create!(brand: @brand, user: @user, brand_membership: membership)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "hookus.test"
  end

  test "requires authentication and a current brand profile" do
    put "/api/v1/profile/prompts", params: { answers: [] }
    assert_response :unauthorized

    @profile.destroy!
    put "/api/v1/profile/prompts", headers: bearer_headers(@token), params: { answers: [] }
    assert_response :forbidden
    assert_equal "profile_required", JSON.parse(response.body).fetch("error")
  end

  test "replaces prompt answers and returns them on the owner profile" do
    put "/api/v1/profile/prompts",
      headers: bearer_headers(@token),
      params: { answers: [ { key: "perfect_night", answer: "Good food and music." } ] }

    assert_response :success
    prompts = JSON.parse(response.body).fetch("profile").fetch("prompts")
    assert_equal "perfect_night", prompts.sole.fetch("key")
    assert_equal "Good food and music.", prompts.sole.fetch("answer")

    get "/api/v1/profile/prompts", headers: bearer_headers(@token)
    assert_response :success
    assert_equal "Good food and music.", JSON.parse(response.body).fetch("prompts").sole.fetch("answer")
  end

  test "rejects unknown prompt keys" do
    put "/api/v1/profile/prompts",
      headers: bearer_headers(@token),
      params: { answers: [ { key: "not_a_prompt", answer: "x" } ] }

    assert_response :unprocessable_entity
    assert_equal "invalid_prompt_answers", JSON.parse(response.body).fetch("error")
  end

  test "rejects a non-array answers payload" do
    put "/api/v1/profile/prompts", headers: bearer_headers(@token), params: { answers: "nope" }

    assert_response :unprocessable_entity
    assert_equal "invalid_prompt_answers", JSON.parse(response.body).fetch("error")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
