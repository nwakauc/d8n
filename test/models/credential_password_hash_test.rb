require "test_helper"

class CredentialPasswordHashTest < ActiveSupport::TestCase
  test "stores a Rodauth password hash for a verified password credential" do
    credential = password_credential

    Identity::PasswordEngine.set!(credential:, password: "long enough password")

    password_record = credential.reload.credential_password_hash
    assert password_record.present?
    assert password_record.password_changed_at.present?
    assert_not_equal "long enough password", password_record.password_hash
    assert Identity::PasswordEngine.matches?(credential:, password: "long enough password")
    assert_not Identity::PasswordEngine.matches?(credential:, password: "wrong password")
  end

  test "replaces the hash without creating a second password record" do
    credential = password_credential
    Identity::PasswordEngine.set!(credential:, password: "original long password")

    assert_no_difference -> { CredentialPasswordHash.count } do
      Identity::PasswordEngine.set!(credential:, password: "replacement password")
    end

    assert_not Identity::PasswordEngine.matches?(credential:, password: "original long password")
    assert Identity::PasswordEngine.matches?(credential:, password: "replacement password")
  end

  test "rejects weak passwords through Rodauth requirements" do
    credential = password_credential

    assert_raises Identity::PasswordEngine::InvalidPassword do
      Identity::PasswordEngine.set!(credential:, password: "short")
    end

    assert_nil credential.reload.credential_password_hash
  end

  test "allows unverified identifiers but rejects non-password credentials" do
    unverified = password_credential(verified_at: nil)
    phone_otp = credential(kind: :phone_otp)

    Identity::PasswordEngine.set!(credential: unverified, password: "long enough password")
    assert Identity::PasswordEngine.matches?(credential: unverified, password: "long enough password")
    assert_raises Identity::PasswordEngine::InvalidCredential do
      Identity::PasswordEngine.set!(credential: phone_otp, password: "long enough password")
    end
  end

  test "treats a corrupt stored password hash as no match" do
    credential = password_credential
    CredentialPasswordHash.create!(
      credential:,
      password_hash: "corrupt",
      password_changed_at: Time.current
    )

    assert_not Identity::PasswordEngine.matches?(credential:, password: "long enough password")
  end

  test "burns a dummy password check without authenticating" do
    assert_equal false, Identity::PasswordEngine.burn(password: "attacker supplied password")
  end

  test "password hash records reject non-password credentials" do
    phone_otp = credential(kind: :phone_otp)
    password_record = CredentialPasswordHash.new(
      credential: phone_otp,
      password_hash: "$2a$12$not-a-real-hash",
      password_changed_at: Time.current
    )

    assert_not password_record.valid?
    assert_includes password_record.errors[:credential], "must use the password strategy"
  end

  test "database permits only one password hash record per credential" do
    credential = password_credential
    Identity::PasswordEngine.set!(credential:, password: "long enough password")

    assert_raises ActiveRecord::RecordNotUnique do
      CredentialPasswordHash.insert_all!([ {
        credential_id: credential.id,
        password_hash: "$2a$12$duplicate",
        password_changed_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "database rejects a password hash for a non-password credential" do
    phone_otp = credential(kind: :phone_otp)

    assert_raises ActiveRecord::InvalidForeignKey do
      CredentialPasswordHash.insert_all!([ {
        credential_id: phone_otp.id,
        credential_kind: Credential.kinds.fetch("password"),
        password_hash: "$2a$12$not-a-real-hash",
        password_changed_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  private

  def password_credential(verified_at: Time.current)
    credential(kind: :password, verified_at:)
  end

  def credential(kind:, verified_at: Time.current)
    user = User.create!
    identifier = IdentityIdentifier.create!(
      user:,
      kind: :phone,
      normalized_value: "+2782123#{SecureRandom.random_number(10000).to_s.rjust(4, '0')}",
      verified_at:
    )
    Credential.create!(user:, identity_identifier: identifier, kind:)
  end
end
