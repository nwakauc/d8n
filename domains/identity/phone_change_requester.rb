module Identity
  class PhoneChangeRequester
    Result = Data.define(:success?, :error, :retry_after)
    PURPOSE = "phone_change".freeze
    EXPIRES_IN = 10.minutes

    def self.call(...)
      new(...).call
    end

    def initialize(session:, phone:, current_password:, ip_address: nil, user_agent: nil)
      @session, @phone_input, @current_password = session, phone, current_password
      @ip_address, @user_agent = ip_address, user_agent
    end

    def call
      return failure(:password_credential_required) unless eligible_credential?
      replacement = LoginIdentifier.call(phone_input)
      return failure(:phone_change_unavailable) unless replacement&.kind == :phone
      return failure(:phone_change_unavailable) unless PasswordEngine.matches?(credential:, password: current_password)
      new_phone = replacement.normalized_value
      return failure(:phone_change_unavailable) if new_phone == identifier.normalized_value || phone_owned?(new_phone)
      throttle = OtpThrottle.call(brand: session.brand, identifier: new_phone, kind: :phone_change, ip_address:)
      return failure(:verification_rate_limited, retry_after: throttle.retry_after) if throttle.throttled?

      challenge = OtpChallenge.create!(brand: session.brand, identity_identifier: identifier,
        kind: :phone_change, identifier: new_phone, code_digest: OtpChallenge.digest_code(code = OtpCode.generate),
        delivery_code: code, expires_at: EXPIRES_IN.from_now, ip_address:, user_agent:,
        metadata: { purpose: PURPOSE, session_id: session.id })
      OtpChallenge.active.where(identity_identifier: identifier, kind: :phone_change).where.not(id: challenge.id)
        .update_all(consumed_at: Time.current, updated_at: Time.current)
      unless Notifications::Sms.configured?(brand: session.brand)
        challenge.consume!
        return failure(:delivery_unavailable)
      end
      Notifications::DeliverChallengeJob.perform_later(challenge.id)
      audit("requested", new_phone:)
      Result.new(true, nil, 0)
    rescue ActiveRecord::RecordNotUnique
      failure(:phone_change_unavailable)
    end

    private
    attr_reader :session, :phone_input, :current_password, :ip_address, :user_agent

    def credential
      @credential ||= session.credential
    end

    def identifier
      @identifier ||= credential&.identity_identifier
    end

    def eligible_credential?
      credential&.password? && credential.active? && credential.deleted_at.nil? &&
        identifier&.phone? && identifier.deleted_at.nil? && credential.user_id == session.user_id
    end

    def phone_owned?(phone)
      IdentityIdentifier.kept.phone.where(normalized_value: phone).where.not(id: identifier.id).exists?
    end

    def audit(outcome, new_phone: nil)
      SecurityEvent.create!(brand: session.brand, user: session.user, event_type: "auth.phone_change.#{outcome}",
        severity: outcome == "succeeded" ? :info : :warning, ip_address:, user_agent:,
        metadata: { old_identifier_last4: identifier.normalized_value.last(4), new_identifier_last4: new_phone&.last(4) }.compact)
    end

    def failure(error, retry_after: 0)
      Result.new(false, error, retry_after)
    end
  end
end
