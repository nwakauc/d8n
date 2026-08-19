require "test_helper"

# Registration must automatically kick off phone/email verification through the
# already-built async delivery seam: create the account, create an OTP challenge,
# and — only after the account transaction commits — enqueue
# Notifications::DeliverChallengeJob. No provider network call happens inside
# registration, and the identifier stays unverified until the code is confirmed.
class Api::V1::Auth::RegistrationVerificationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @brand = Brand.create!(
      slug: "hookus",
      name: "HookUs",
      auth_methods: %w[ phone_password email_password ]
    )
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    host! "hookus.test"
    Notifications::Sms::TestGateway.clear
    ActionMailer::Base.deliveries.clear
  end

  # ---- PHONE -------------------------------------------------------------

  test "phone registration creates an unverified identifier, a phone challenge, and enqueues async SMS delivery" do
    with_sms_provider("test") do
      assert_difference -> { OtpChallenge.phone_verification.count }, 1 do
        assert_enqueued_jobs 1, only: Notifications::DeliverChallengeJob do
          post "/api/v1/auth/password/register", params: phone_registration
        end
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal true, body.fetch("verification_required")
    assert_equal "phone", body.fetch("verification_channel")
    assert_equal false, body.fetch("identifier").fetch("verified")

    identifier = IdentityIdentifier.phone.last
    assert_nil identifier.verified_at, "registration must not pretend the phone is verified"

    challenge = OtpChallenge.phone_verification.last
    assert_equal identifier, challenge.identity_identifier
    assert_equal @brand, challenge.brand
    assert_equal "identifier_verification", challenge.metadata.fetch("purpose")

    # Enqueued after commit, carrying ONLY the challenge id — never the plaintext code.
    job = enqueued_jobs.find { |enqueued| enqueued[:job] == Notifications::DeliverChallengeJob }
    assert_equal [ challenge.id ], job[:args]
    assert_no_match(/\b\d{6}\b/, job[:args].join(","))

    # The provider was NOT invoked inline during registration.
    assert_empty Notifications::Sms::TestGateway.deliveries
    assert_equal 0, NotificationDelivery.count
  end

  # ---- EMAIL -------------------------------------------------------------

  test "email registration creates an email challenge and enqueues async email delivery without sending inline" do
    assert_difference -> { OtpChallenge.email_verification.count }, 1 do
      assert_enqueued_jobs 1, only: Notifications::DeliverChallengeJob do
        post "/api/v1/auth/password/register", params: email_registration
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal true, body.fetch("verification_required")
    assert_equal "email", body.fetch("verification_channel")

    identifier = IdentityIdentifier.email.last
    assert_nil identifier.verified_at

    challenge = OtpChallenge.email_verification.last
    assert_equal identifier, challenge.identity_identifier
    assert_equal [ challenge.id ], enqueued_jobs.find { |e| e[:job] == Notifications::DeliverChallengeJob }[:args]

    # No mail is delivered inside the registration request.
    assert_empty ActionMailer::Base.deliveries
    assert_equal 0, NotificationDelivery.count
  end

  # ---- ASYNC / FAILURE ---------------------------------------------------

  test "a misconfigured provider fails closed but never rolls back the committed account" do
    result = with_sms_provider("required") do
      assert_difference -> { User.count }, 1 do
        assert_no_enqueued_jobs do
          post "/api/v1/auth/password/register", params: phone_registration
        end
      end
    end
    _ = result

    # The account, identifier, credential, membership and session are all committed.
    assert_response :created
    identifier = IdentityIdentifier.phone.last
    assert_nil identifier.verified_at
    assert BrandMembership.exists?(user: identifier.user, brand: @brand)

    # Delivery failed closed: the challenge is consumed and nothing was enqueued.
    challenge = OtpChallenge.phone_verification.last
    assert challenge.consumed?, "a challenge that cannot be delivered is consumed"

    # The frontend is still told verification is required (it never learns the phone is verified).
    assert_equal true, JSON.parse(response.body).fetch("verification_required")
  end

  # ---- ABUSE / DUPLICATE -------------------------------------------------

  test "duplicate registration does not create a second identity, challenge, or delivery job" do
    with_sms_provider("test") do
      post "/api/v1/auth/password/register", params: phone_registration
    end
    assert_response :created

    with_sms_provider("test") do
      assert_no_difference -> { User.count } do
        assert_no_difference -> { OtpChallenge.count } do
          assert_no_enqueued_jobs do
            post "/api/v1/auth/password/register", params: phone_registration
          end
        end
      end
    end

    assert_response :unprocessable_entity
    assert_equal({ "error" => "registration_unavailable" }, JSON.parse(response.body))
  end

  # ---- BRAND ISOLATION ---------------------------------------------------

  test "registration resolves the host brand for delivery and never falls back to another brand" do
    date9ja = Brand.create!(slug: "date9ja", name: "Date9ja", auth_methods: %w[ phone_password email_password ])
    BrandDomain.create!(brand: date9ja, host: "date9ja.test")
    host! "date9ja.test"

    with_sms_provider("test") do
      perform_enqueued_jobs do
        post "/api/v1/auth/password/register", params: phone_registration
      end
    end

    assert_response :created
    assert_equal date9ja, OtpChallenge.phone_verification.last.brand

    delivery = Notifications::Sms::TestGateway.deliveries.last
    assert_equal date9ja.id, delivery.fetch(:brand_id)
    assert_includes delivery.fetch(:body), "Date9ja"
    assert_no_match(/HookUs/, delivery.fetch(:body), "must not leak the other brand's sender identity")
  end

  # ---- VERIFICATION E2E --------------------------------------------------

  test "the delivered code verifies the identifier; a wrong code does not and the code cannot be replayed" do
    with_sms_provider("test") do
      post "/api/v1/auth/password/register", params: phone_registration
    end
    assert_response :created
    token = JSON.parse(response.body).fetch("token")

    challenge = OtpChallenge.phone_verification.last
    code = challenge.delivery_code # decrypts the ciphertext stored at creation
    assert_match(/\A\d{6}\z/, code)

    # Wrong code leaves the identifier unverified.
    patch "/api/v1/auth/verification", headers: bearer(token), params: { kind: "phone", code: "000000" }
    assert_response :unauthorized
    assert_nil challenge.identity_identifier.reload.verified_at

    # The real code verifies the identifier and consumes the challenge so it can
    # never be replayed to verify a different, still-unverified identifier.
    patch "/api/v1/auth/verification", headers: bearer(token), params: { kind: "phone", code: }
    assert_response :success
    assert challenge.identity_identifier.reload.verified_at.present?
    assert challenge.reload.consumed?
  end

  # ---- GOOGLE / THIRD-PARTY ---------------------------------------------

  test "google is not an implemented registration path, so no email OTP is forced through this flow" do
    @brand.update!(auth_methods: %w[ phone_password email_password google ])

    # Google is declared but unimplemented: it is never surfaced as an available
    # method and there is no signup route, so registration never triggers an OTP
    # for a (would-be) provider-trusted email. Trust of a Google-verified email is
    # deferred to a future OAuth flow, not this password path.
    assert_not_includes Identity::AuthPolicy::IMPLEMENTED_METHODS, "google"
    assert_not_includes Identity::AuthPolicy.available_methods(brand: @brand), "google"
    post "/api/v1/auth/google", params: {}
    assert_response :not_found
  end

  private

  def phone_registration
    { identifier: "+27 82 123 4567", password: "secret", device_name: "Web" }
  end

  def email_registration
    { identifier: "ada@example.com", password: "secret", device_name: "Web" }
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def with_sms_provider(provider)
    previous = ENV["D8N_SMS_PROVIDER"]
    ENV["D8N_SMS_PROVIDER"] = provider
    yield
  ensure
    ENV["D8N_SMS_PROVIDER"] = previous
  end
end
