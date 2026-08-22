require "test_helper"

class DeviceRegistrationTest < ActiveSupport::TestCase
  test "encrypts the token and rejects cross-brand ownership" do
    dateza = Brand.create!(slug: "dateza", name: "DateZA")
    hookus = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    membership = BrandMembership.create!(brand: dateza, user:, status: :active)
    device = DeviceRegistration.create!(
      brand: dateza,
      user:,
      brand_membership: membership,
      platform: :ios,
      token: "secret-push-token",
      last_seen_at: Time.current
    )

    raw_token = DeviceRegistration.connection.select_value(
      "SELECT token FROM device_registrations WHERE id = #{device.id}"
    )
    assert_not_equal "secret-push-token", raw_token
    assert_equal "secret-push-token", device.reload.token

    device.brand = hookus
    assert_not device.valid?
    assert_includes device.errors[:brand_membership], "must belong to the device brand and user"
  end
end
