module Identity
  class PasswordRegistration
    Result = Data.define(:success?, :error, :user, :credential, :session, :raw_token, :retry_after)
    PURPOSE = "password_registration"

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, identifier:, password:, device_name: nil, ip_address: nil, user_agent: nil)
      @brand = brand
      @identifier_input = identifier
      @password = password
      @device_name = device_name
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure(:brand_required) unless active_brand?

      login_identifier = LoginIdentifier.call(identifier_input)
      return invalid_registration unless login_identifier
      return failure(:auth_method_unavailable) unless AuthPolicy.enabled?(brand:, method: login_identifier.auth_method)
      return invalid_registration(login_identifier) unless PasswordEngine.valid?(password:)

      registration = register(login_identifier)
      deliver_verification(registration.user, login_identifier) if registration.success?
      registration
    end

    private

    attr_reader :brand, :identifier_input, :password, :device_name, :ip_address, :user_agent

    # Kicks off phone/email verification through the shared OTP delivery seam AFTER
    # the account transaction has committed. Registration proves a password, never
    # control of the contact identifier, so the just-created identifier stays
    # unverified until the code is confirmed; this only creates the challenge and
    # enqueues async delivery (Notifications::DeliverChallengeJob) — no provider I/O
    # runs here or inside the registration transaction.
    #
    # The account already exists and is committed, so a throttled or misconfigured
    # delivery here must NOT roll it back or fail the request: VerificationRequester
    # fails closed on its own (silent non-delivery / consumed challenge), the
    # identifier simply remains unverified, and the standard resend endpoint recovers.
    # The result is therefore intentionally not propagated.
    def deliver_verification(user, login_identifier)
      VerificationRequester.call(
        user:,
        brand:,
        kind: login_identifier.kind,
        ip_address:,
        user_agent:
      )
    end

    def register(login_identifier)
      result = nil

      ActiveRecord::Base.transaction do
        AuthenticationLock.with_lock(
          brand:,
          purpose: PURPOSE,
          identifier: login_identifier.normalized_value,
          ip_address:
        ) do
          throttle = PasswordThrottle.call(
            brand:,
            purpose: PURPOSE,
            identifier: login_identifier.normalized_value,
            ip_address:
          )
          if throttle.throttled?
            audit(login_identifier, result: :throttled, retry_after: throttle.retry_after)
            result = failure(:rate_limited, retry_after: throttle.retry_after)
          elsif IdentityIdentifier.where(
            kind: login_identifier.kind,
            normalized_value: login_identifier.normalized_value
          ).exists?
            PasswordEngine.burn(password:)
            audit(login_identifier, result: :failed)
            result = failure(:registration_unavailable)
          else
            result = create_account(login_identifier)
          end
        end
      end

      result
    rescue ActiveRecord::RecordNotUnique
      audit(login_identifier, result: :failed)
      failure(:registration_unavailable)
    end

    def create_account(login_identifier)
      user = User.create!
      identity_identifier = user.identity_identifiers.create!(
        kind: login_identifier.kind,
        normalized_value: login_identifier.normalized_value,
        verified_at: nil,
        last_seen_at: Time.current
      )
      credential = user.credentials.create!(
        identity_identifier:,
        kind: :password,
        status: :active,
        verified_at: nil
      )
      PasswordEngine.set!(credential:, password:)
      membership = BrandMembership.create!(user:, brand:, status: :active)
      Notifications::EventPublisher.membership_registered!(membership:)
      raw_token, session = Session.issue!(
        user:,
        brand:,
        credential:,
        device_name:,
        ip_address:,
        user_agent:
      )
      credential.update!(last_used_at: Time.current)
      audit(login_identifier, result: :succeeded, user:, identity_identifier:, credential:)

      Result.new(true, nil, user, credential, session, raw_token, nil)
    end

    def invalid_registration(login_identifier = nil)
      PasswordEngine.burn(password:) if login_identifier.nil?
      audit(login_identifier, result: :failed)
      failure(:registration_unavailable)
    end

    def audit(login_identifier, result:, user: nil, identity_identifier: nil, credential: nil, retry_after: nil)
      PasswordAudit.record!(
        brand:,
        purpose: PURPOSE,
        result:,
        identifier: login_identifier&.normalized_value,
        identifier_kind: login_identifier&.kind,
        ip_address:,
        user_agent:,
        user:,
        identity_identifier:,
        credential:,
        retry_after:
      )
    end

    def active_brand?
      brand.present? && brand.active? && brand.deleted_at.nil?
    end

    def failure(error, retry_after: nil)
      Result.new(false, error, nil, nil, nil, nil, retry_after)
    end
  end
end
