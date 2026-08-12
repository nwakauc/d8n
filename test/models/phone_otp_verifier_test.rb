require "test_helper"

module Identity
  class PhoneOtpVerifierTest < ActiveSupport::TestCase
    test "recovers when another request creates the same phone identity first" do
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      existing_user = User.create!
      verifier = PhoneOtpVerifier.new(brand:, phone: "+27 82 123 4567", code: "123456")

      verifier.define_singleton_method(:create_user_and_identifier) do |identifier|
        existing_user.identity_identifiers.create!(
          kind: :phone,
          normalized_value: identifier,
          verified_at: Time.current
        )
        raise ActiveRecord::RecordNotUnique, "duplicate phone identifier"
      end

      user, identity_identifier = verifier.send(:user_and_identifier, "27821234567")

      assert_equal existing_user, user
      assert_equal "27821234567", identity_identifier.normalized_value
      assert_equal 1, IdentityIdentifier.where(kind: :phone, normalized_value: "27821234567").count
    end
  end
end
