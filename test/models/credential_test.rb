require "test_helper"

class CredentialTest < ActiveSupport::TestCase
  test "requires identifier to belong to credential user" do
    user = User.create!
    other_user = User.create!
    identifier = IdentityIdentifier.create!(user: other_user, kind: :phone, normalized_value: "+27821234567")

    credential = Credential.new(user:, identity_identifier: identifier, kind: :phone_otp)

    assert_not credential.valid?
    assert_includes credential.errors[:identity_identifier], "must belong to the credential user"
  end

  test "enforces one active credential per user kind and identifier" do
    user = User.create!
    identifier = IdentityIdentifier.create!(user:, kind: :phone, normalized_value: "+27821234567")

    Credential.create!(user:, identity_identifier: identifier, kind: :phone_otp)
    duplicate = Credential.new(user:, identity_identifier: identifier, kind: :phone_otp)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:identity_identifier_id], "has already been taken"
  end
end
