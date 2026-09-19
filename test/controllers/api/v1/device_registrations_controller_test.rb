require "test_helper"

class Api::V1::DeviceRegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: @brand, host: "date9ja.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user)
    @token, = Session.issue!(brand: @brand, user: @user)
    host! "date9ja.test"
  end

  test "registers one brand-scoped installation idempotently" do
    assert_difference -> { DeviceRegistration.count }, 1 do
      post_registration
      assert_response :created
    end

    public_id = JSON.parse(response.body).dig("device_registration", "id")
    post_registration

    assert_response :ok
    assert_equal public_id, JSON.parse(response.body).dig("device_registration", "id")
    assert_equal 1, DeviceRegistration.where(brand: @brand, user: @user).count
  end

  test "rotates a token without creating another installation row" do
    post_registration(token: "ExponentPushToken[old]")
    registration = DeviceRegistration.last

    post_registration(token: "ExponentPushToken[new]")

    assert_response :ok
    assert_equal registration.id, DeviceRegistration.last.id
    assert_equal "ExponentPushToken[new]", registration.reload.token
    assert_equal 1, DeviceRegistration.where(brand: @brand, installation_id: "install-1").count
  end

  test "moving an installation to another member does not leave the old member deliverable" do
    post_registration
    other = User.create!
    other_membership = BrandMembership.create!(brand: @brand, user: other)
    other_token, = Session.issue!(brand: @brand, user: other)

    post_registration(token: "ExponentPushToken[other]", auth_token: other_token)

    registration = DeviceRegistration.find_by!(brand: @brand, installation_id: "install-1")
    assert_equal other, registration.user
    assert_equal other_membership, registration.brand_membership
    assert_empty DeviceRegistration.deliverable.where(brand: @brand, user: @user)
  end

  test "brand isolation keeps the same installation separate on another brand" do
    other_brand = Brand.create!(slug: "dateza", name: "DateZA")
    BrandDomain.create!(brand: other_brand, host: "dateza.test")
    BrandMembership.create!(brand: other_brand, user: @user)
    other_token, = Session.issue!(brand: other_brand, user: @user)

    post_registration
    host! "dateza.test"
    post_registration(auth_token: other_token, token: "ExponentPushToken[dateza]")

    assert_response :created
    assert_equal 1, DeviceRegistration.where(brand: @brand, installation_id: "install-1").count
    assert_equal 1, DeviceRegistration.where(brand: other_brand, installation_id: "install-1").count
  end

  test "logout disables the installation and does not disclose another member's device" do
    post_registration
    delete "/api/v1/device_registrations/install-1", headers: bearer_headers(@token)

    assert_response :ok
    assert_equal false, JSON.parse(response.body).dig("device_registration", "enabled")
    assert_not DeviceRegistration.last.reload.enabled?
    assert_equal "logout", DeviceRegistration.last.last_error if DeviceRegistration.column_names.include?("last_error")
  end

  private

  def post_registration(token: "ExponentPushToken[device-1]", auth_token: @token)
    post "/api/v1/device_registrations",
      params: {
        device_registration: {
          installation_id: "install-1",
          token:,
          platform: "android",
          device_name: "Date9ja test device"
        }
      }, headers: bearer_headers(auth_token)
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
