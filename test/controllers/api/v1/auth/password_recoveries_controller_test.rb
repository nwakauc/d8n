require "test_helper"

class Api::V1::Auth::PasswordRecoveriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @brand = Brand.create!(
      slug: "hookus",
      name: "HookUs",
      auth_methods: %w[ phone_password email_password ]
    )
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    @user = User.create!
    @membership = BrandMembership.create!(brand: @brand, user: @user, status: :active)
    @phone = @user.identity_identifiers.create!(
      kind: :phone, normalized_value: "+27 82 123 4567", verified_at: Time.current
    )
    @credential = @user.credentials.create!(identity_identifier: @phone, kind: :password, status: :active)
    Identity::PasswordEngine.set!(credential: @credential, password: "secret")
    host! "hookus.test"
    Notifications::Sms::TestGateway.clear
    ActionMailer::Base.deliveries.clear
    # Delivery is now enqueued after commit (Notifications::DeliverChallengeJob).
    # Run it inline so these end-to-end recovery specs still observe the delivered
    # code/email synchronously; the async contract itself is covered by the job's
    # own tests.
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  # --- Request step (anti-enumeration) -------------------------------------

  test "eligible verified identifier can start recovery" do
    with_sms_provider("test") do
      assert_difference -> { OtpChallenge.password_recovery.count }, 1 do
        post "/api/v1/auth/password/recovery", params: { identifier: "+27 82 123 4567" }
      end
    end

    assert_response :accepted
    assert_equal({ "message" => neutral_message }, JSON.parse(response.body))
    challenge = OtpChallenge.password_recovery.last
    assert_equal @phone, challenge.identity_identifier
    assert_equal "password_recovery", challenge.metadata.fetch("purpose")
    assert_in_delta 10.minutes.from_now.to_i, challenge.expires_at.to_i, 5
    assert_equal "27821234567", Notifications::Sms::TestGateway.deliveries.last.fetch(:to)
    assert SecurityEvent.exists?(event_type: "auth.password_recovery.requested", user: @user)
  end

  test "nonexistent identifier returns the same neutral response and creates nothing" do
    known = with_sms_provider("test") do
      post "/api/v1/auth/password/recovery", params: { identifier: "+27 82 123 4567" }
      response.body
    end

    assert_no_difference -> { OtpChallenge.count } do
      with_sms_provider("test") do
        post "/api/v1/auth/password/recovery", params: { identifier: "+27 82 999 9999" }
      end
    end

    assert_response :accepted
    assert_equal known, response.body
    assert_equal({ "message" => neutral_message }, JSON.parse(response.body))
  end

  test "unverified identifier never becomes a recovery channel" do
    @phone.update!(verified_at: nil)

    assert_no_difference -> { OtpChallenge.count } do
      with_sms_provider("test") do
        post "/api/v1/auth/password/recovery", params: { identifier: "+27 82 123 4567" }
      end
    end

    assert_response :accepted
    assert_equal({ "message" => neutral_message }, JSON.parse(response.body))
    assert_empty Notifications::Sms::TestGateway.deliveries
  end

  test "identity without a membership in the requesting brand is not a recovery channel" do
    @membership.destroy!

    assert_no_difference -> { OtpChallenge.count } do
      with_sms_provider("test") do
        post "/api/v1/auth/password/recovery", params: { identifier: "+27 82 123 4567" }
      end
    end

    assert_response :accepted
  end

  test "missing identifier is a request-shape error, not an account signal" do
    post "/api/v1/auth/password/recovery", params: {}

    assert_response :unprocessable_entity
    assert_equal({ "error" => "invalid_request" }, JSON.parse(response.body))
  end

  test "repeated recovery requests are throttled into silent non-delivery, still neutral" do
    5.times do |i|
      OtpChallenge.create!(
        brand: @brand, identity_identifier: @phone, kind: :password_recovery,
        identifier: @phone.normalized_value, code_digest: OtpChallenge.digest_code("x#{i}"),
        expires_at: 10.minutes.from_now, created_at: (i + 1).minutes.ago
      )
    end

    assert_no_difference -> { OtpChallenge.password_recovery.count } do
      with_sms_provider("test") do
        post "/api/v1/auth/password/recovery", params: { identifier: "+27 82 123 4567" }
      end
    end

    assert_response :accepted
    assert_equal({ "message" => neutral_message }, JSON.parse(response.body))
    assert_empty Notifications::Sms::TestGateway.deliveries
    assert SecurityEvent.exists?(event_type: "auth.password_recovery.throttled", user: @user)
  end

  test "delivers a recovery code by email for an email-backed credential" do
    email = @user.identity_identifiers.create!(
      kind: :email, normalized_value: "ada@example.com", verified_at: Time.current
    )
    @user.credentials.create!(identity_identifier: email, kind: :password, status: :active).then do |cred|
      Identity::PasswordEngine.set!(credential: cred, password: "secret")
    end

    assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
      post "/api/v1/auth/password/recovery", params: { identifier: " ADA@EXAMPLE.COM " }
    end

    assert_response :accepted
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "ada@example.com" ], mail.to
    assert_match(/reset your hookus password/i, mail.subject)
    assert mail.text_part.body.to_s[/\b\d{6}\b/].present?
  end

  # --- Verify step ----------------------------------------------------------

  test "verifying with a valid code returns a single-use reset token" do
    request_recovery
    code = delivered_code

    post "/api/v1/auth/password/recovery/verify", params: { identifier: "+27 82 123 4567", code: }

    assert_response :created
    body = JSON.parse(response.body)
    assert body.fetch("reset_token").present?
    assert body.fetch("expires_at").present?
    assert OtpChallenge.password_recovery.last.consumed?
    assert OtpChallenge.password_reset.active.exists?(identity_identifier: @phone)
    assert SecurityEvent.exists?(event_type: "auth.password_recovery.verified", user: @user)
  end

  test "verify returns generic invalid_code for wrong code and for unknown identifier" do
    request_recovery

    post "/api/v1/auth/password/recovery/verify", params: { identifier: "+27 82 123 4567", code: "000000" }
    wrong = response.body
    assert_response :unauthorized

    post "/api/v1/auth/password/recovery/verify", params: { identifier: "+27 82 999 9999", code: "000000" }
    assert_response :unauthorized
    assert_equal wrong, response.body
    assert_equal({ "error" => "invalid_code" }, JSON.parse(response.body))
  end

  test "verify rejects an expired recovery code" do
    request_recovery
    code = delivered_code
    OtpChallenge.password_recovery.last.update!(expires_at: 1.minute.ago)

    post "/api/v1/auth/password/recovery/verify",
      params: { identifier: "+27 82 123 4567", code: }

    assert_response :gone
    assert_equal({ "error" => "verification_code_expired" }, JSON.parse(response.body))

    post "/api/v1/auth/password/recovery/verify",
      params: { identifier: "+27 82 123 4567", code: "000000" }
    assert_response :unauthorized
    assert_equal({ "error" => "invalid_code" }, JSON.parse(response.body))
  end

  test "verify locks a recovery code after five wrong attempts" do
    request_recovery
    challenge = OtpChallenge.password_recovery.last

    4.times do
      post "/api/v1/auth/password/recovery/verify",
        params: { identifier: "+27 82 123 4567", code: "000000" }
      assert_response :unauthorized
    end

    post "/api/v1/auth/password/recovery/verify",
      params: { identifier: "+27 82 123 4567", code: "000000" }
    assert_response :too_many_requests
    assert_equal({ "error" => "verification_attempts_exhausted" }, JSON.parse(response.body))

    assert challenge.reload.consumed?
    post "/api/v1/auth/password/recovery/verify",
      params: { identifier: "+27 82 123 4567", code: delivered_code }
    assert_response :too_many_requests
    assert_equal({ "error" => "verification_attempts_exhausted" }, JSON.parse(response.body))
  end

  test "a consumed recovery code is only disclosed to its holder" do
    request_recovery
    code = delivered_code
    post "/api/v1/auth/password/recovery/verify", params: { identifier: "+27 82 123 4567", code: }
    assert_response :created

    post "/api/v1/auth/password/recovery/verify", params: { identifier: "+27 82 123 4567", code: }
    assert_response :conflict
    assert_equal({ "error" => "verification_code_used" }, JSON.parse(response.body))

    post "/api/v1/auth/password/recovery/verify",
      params: { identifier: "+27 82 123 4567", code: "000000" }
    assert_response :unauthorized
    assert_equal({ "error" => "invalid_code" }, JSON.parse(response.body))
  end

  # --- Reset step -----------------------------------------------------------

  test "reset changes the password and is single-use" do
    token = obtain_reset_token

    post "/api/v1/auth/password/recovery/reset",
      params: { reset_token: token, password: "new-secret", password_confirmation: "new-secret" }

    assert_response :success
    assert_equal({ "message" => "Password reset. Sign in with your new password." }, JSON.parse(response.body))
    assert Identity::PasswordEngine.matches?(credential: @credential.reload, password: "new-secret")
    assert_not Identity::PasswordEngine.matches?(credential: @credential, password: "secret")

    post "/api/v1/auth/password/recovery/reset",
      params: { reset_token: token, password: "another-secret", password_confirmation: "another-secret" }
    assert_response :unauthorized
    assert_equal({ "error" => "invalid_or_expired_token" }, JSON.parse(response.body))
    assert Identity::PasswordEngine.matches?(credential: @credential.reload, password: "new-secret")
  end

  test "reset reuses the shared password policy and keeps the token usable on rejection" do
    token = obtain_reset_token

    post "/api/v1/auth/password/recovery/reset",
      params: { reset_token: token, password: "short", password_confirmation: "short" }
    assert_response :unprocessable_entity
    assert_equal({ "error" => "invalid_password" }, JSON.parse(response.body))

    post "/api/v1/auth/password/recovery/reset",
      params: { reset_token: token, password: "new-secret", password_confirmation: "mismatch" }
    assert_response :unprocessable_entity

    # The authorization survived the invalid attempts and still works.
    post "/api/v1/auth/password/recovery/reset",
      params: { reset_token: token, password: "new-secret", password_confirmation: "new-secret" }
    assert_response :success
  end

  test "reset rejects an unknown or expired token without revealing anything" do
    post "/api/v1/auth/password/recovery/reset",
      params: { reset_token: "not-a-real-token", password: "new-secret", password_confirmation: "new-secret" }
    assert_response :unauthorized
    assert_equal({ "error" => "invalid_or_expired_token" }, JSON.parse(response.body))

    token = obtain_reset_token
    OtpChallenge.password_reset.active.last.update!(expires_at: 1.minute.ago)
    post "/api/v1/auth/password/recovery/reset",
      params: { reset_token: token, password: "new-secret", password_confirmation: "new-secret" }
    assert_response :unauthorized
    assert Identity::PasswordEngine.matches?(credential: @credential.reload, password: "secret")
  end

  # --- Centerpiece flow -----------------------------------------------------

  test "full recovery revokes every existing session across brands and rotates the password" do
    other_brand = Brand.create!(slug: "date9ja", name: "Date9ja", auth_methods: %w[ phone_password ])
    BrandMembership.create!(user: @user, brand: other_brand, status: :active)
    _, hookus_session = Session.issue!(user: @user, brand: @brand, credential: @credential)
    _, other_session = Session.issue!(user: @user, brand: other_brand, credential: @credential)

    token = obtain_reset_token
    post "/api/v1/auth/password/recovery/reset",
      params: { reset_token: token, password: "new-secret", password_confirmation: "new-secret" }
    assert_response :success

    assert hookus_session.reload.revoked?
    assert other_session.reload.revoked?
    assert_not Identity::PasswordEngine.matches?(credential: @credential.reload, password: "secret")

    # Old password no longer authenticates; new password does (membership active).
    post "/api/v1/auth/password/login", params: { identifier: "+27 82 123 4567", password: "secret" }
    assert_response :unauthorized
    post "/api/v1/auth/password/login", params: { identifier: "+27 82 123 4567", password: "new-secret" }
    assert_response :created

    event = SecurityEvent.find_by!(event_type: "auth.password_recovery.succeeded", user: @user)
    assert_equal 2, event.metadata.fetch("revoked_session_count")
  end

  # --- Lifecycle boundaries -------------------------------------------------

  test "suspended user can reset the password but still cannot authenticate" do
    @user.update!(status: :suspended)
    token = obtain_reset_token

    post "/api/v1/auth/password/recovery/reset",
      params: { reset_token: token, password: "new-secret", password_confirmation: "new-secret" }
    assert_response :success
    assert Identity::PasswordEngine.matches?(credential: @credential.reload, password: "new-secret")

    post "/api/v1/auth/password/login", params: { identifier: "+27 82 123 4567", password: "new-secret" }
    assert_response :unauthorized
    assert @user.reload.suspended?
  end

  test "recovery on a left HookUs membership does not restore access or recreate records" do
    @membership.update!(status: :left)

    token = nil
    assert_no_difference -> { BrandMembership.count } do
      assert_no_difference -> { Profile.count } do
        token = obtain_reset_token
        post "/api/v1/auth/password/recovery/reset",
          params: { reset_token: token, password: "new-secret", password_confirmation: "new-secret" }
      end
    end
    assert_response :success

    # Identity-level reset worked, but the brand membership stays `left`...
    assert Identity::PasswordEngine.matches?(credential: @credential.reload, password: "new-secret")
    assert @membership.reload.left?

    # ...and login cannot silently reactivate the left membership.
    post "/api/v1/auth/password/login", params: { identifier: "+27 82 123 4567", password: "new-secret" }
    assert_response :unauthorized
    assert @membership.reload.left?
  end

  test "recovery never records raw codes, tokens, or passwords" do
    request_recovery
    code = delivered_code
    post "/api/v1/auth/password/recovery/verify", params: { identifier: "+27 82 123 4567", code: }
    token = JSON.parse(response.body).fetch("reset_token")
    post "/api/v1/auth/password/recovery/reset",
      params: { reset_token: token, password: "new-secret", password_confirmation: "new-secret" }
    assert_response :success

    secrets = [ code, token, "new-secret", "secret" ]
    SecurityEvent.where(user: @user).find_each do |event|
      secrets.each { |secret| assert_not_includes event.metadata.to_json, secret }
    end
    AuthAttempt.where(user: @user).find_each do |attempt|
      secrets.each { |secret| assert_not_includes attempt.metadata.to_json, secret }
    end
  end

  private

  def neutral_message
    Api::V1::Auth::PasswordRecoveriesController::NEUTRAL_MESSAGE
  end

  def request_recovery
    with_sms_provider("test") do
      post "/api/v1/auth/password/recovery", params: { identifier: "+27 82 123 4567" }
    end
    assert_response :accepted
  end

  def delivered_code
    Notifications::Sms::TestGateway.deliveries.last.fetch(:body)[/\b\d{6}\b/]
  end

  def obtain_reset_token
    request_recovery
    post "/api/v1/auth/password/recovery/verify",
      params: { identifier: "+27 82 123 4567", code: delivered_code }
    assert_response :created
    JSON.parse(response.body).fetch("reset_token")
  end

  def with_sms_provider(provider)
    previous = ENV["D8N_SMS_PROVIDER"]
    ENV["D8N_SMS_PROVIDER"] = provider
    yield
  ensure
    ENV["D8N_SMS_PROVIDER"] = previous
  end
end
