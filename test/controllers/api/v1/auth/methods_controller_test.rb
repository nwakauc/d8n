require "test_helper"

class Api::V1::Auth::MethodsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(
      slug: "hookus",
      name: "HookUs",
      auth_methods: %w[ phone_password email_password phone_otp google ]
    )
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    host! "hookus.test"
  end

  test "returns only implemented methods enabled for the resolved brand" do
    get "/api/v1/auth/methods"

    assert_response :success
    assert_equal(
      {
        "brand" => { "slug" => "hookus", "name" => "HookUs" },
        "methods" => %w[ phone_password email_password phone_otp ]
      },
      JSON.parse(response.body)
    )
  end

  test "does not advertise configured Google until its implementation ships" do
    get "/api/v1/auth/methods"

    assert_not_includes JSON.parse(response.body).fetch("methods"), "google"
  end

  test "does not require authentication" do
    get "/api/v1/auth/methods"

    assert_response :success
  end

  test "requires a resolved active brand" do
    host! "unknown.test"

    get "/api/v1/auth/methods"

    assert_response :not_found
    assert_equal({ "error" => "brand_required" }, JSON.parse(response.body))
  end
end
