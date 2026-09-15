require "test_helper"

class CredentialTest < ActiveSupport::TestCase
  test "requires identifier to belong to credential user" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    other_user = User.create!
    identifier = IdentityIdentifier.create!(user: other_user, brand:, kind: :phone, normalized_value: "+27821234567")

    credential = Credential.new(user:, identity_identifier: identifier, kind: :phone_otp)

    assert_not credential.valid?
    assert_includes credential.errors[:identity_identifier], "must belong to the credential user"
  end

  test "enforces one active credential per user kind and identifier" do
    brand = Brand.create!(slug: "hookus", name: "HookUs")
    user = User.create!
    identifier = IdentityIdentifier.create!(user:, brand:, kind: :phone, normalized_value: "+27821234567")

    Credential.create!(user:, identity_identifier: identifier, kind: :phone_otp)
    duplicate = Credential.new(user:, identity_identifier: identifier, kind: :phone_otp)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:identity_identifier_id], "has already been taken"
  end

  test "two independent brand-scoped users can hold their own credential for the same underlying email value" do
    brand_a = Brand.create!(slug: "hookus", name: "HookUs")
    brand_b = Brand.create!(slug: "dateza", name: "DateZA")
    user_a = User.create!
    user_b = User.create!
    identifier_a = IdentityIdentifier.create!(user: user_a, brand: brand_a, kind: :email, normalized_value: "same@example.com")
    identifier_b = IdentityIdentifier.create!(user: user_b, brand: brand_b, kind: :email, normalized_value: "same@example.com")

    credential_a = Credential.create!(user: user_a, identity_identifier: identifier_a, kind: :password)
    credential_b = Credential.create!(user: user_b, identity_identifier: identifier_b, kind: :password)

    assert credential_a.persisted?
    assert credential_b.persisted?
    assert_not_equal credential_a.user, credential_b.user
  end
end
