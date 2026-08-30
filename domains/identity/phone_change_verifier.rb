module Identity
  class PhoneChangeVerifier
    Result = Data.define(:success?, :error, :revoked_session_count)
    MAX_ATTEMPTS = 5

    def self.call(...)
      new(...).call
    end

    def initialize(session:, phone:, code:, ip_address: nil, user_agent: nil)
      @session, @phone_input, @code = session, phone, code.to_s
      @ip_address, @user_agent = ip_address, user_agent
    end

    def call
      return failure(:verification_code_invalid) unless eligible_credential?
      replacement = LoginIdentifier.call(phone_input)
      return failure(:verification_code_invalid) unless replacement&.kind == :phone
      new_phone = replacement.normalized_value
      challenge = OtpChallenge.where(brand: session.brand, identity_identifier: identifier, kind: :phone_change,
        identifier: new_phone).where("metadata ->> 'session_id' = ?", session.id.to_s).order(created_at: :desc).first
      return failure(:verification_code_invalid) unless challenge
      challenge.with_lock do
        return failure(:verification_code_expired) if challenge.expired?
        return failure(:verification_code_used) if challenge.consumed?
        return failure(:verification_attempts_exhausted) if challenge.attempt_count >= MAX_ATTEMPTS
        unless challenge.code_matches?(code)
          challenge.increment!(:attempt_count)
          challenge.consume! if challenge.attempt_count >= MAX_ATTEMPTS
          audit("failed", new_phone:)
          return failure(challenge.attempt_count >= MAX_ATTEMPTS ? :verification_attempts_exhausted : :verification_code_invalid)
        end
        return failure(:phone_change_unavailable) if phone_owned?(new_phone)
        old_phone = identifier.normalized_value
        challenge.consume!
        identifier.update!(normalized_value: new_phone, verified_at: Time.current, last_seen_at: Time.current)
        revoked = Session.active.where(user: session.user, credential:).where.not(id: session.id).update_all(revoked_at: Time.current, updated_at: Time.current)
        audit("succeeded", old_phone:, new_phone:, revoked_session_count: revoked)
        return Result.new(true, nil, revoked)
      end
    rescue ActiveRecord::RecordNotUnique
      failure(:phone_change_unavailable)
    end

    private
    attr_reader :session, :phone_input, :code, :ip_address, :user_agent
    def credential = (@credential ||= session.credential)
    def identifier = (@identifier ||= credential&.identity_identifier)
    def eligible_credential? = credential&.password? && credential.active? && credential.deleted_at.nil? && identifier&.phone? && identifier.deleted_at.nil? && credential.user_id == session.user_id
    def phone_owned?(phone) = IdentityIdentifier.kept.phone.where(normalized_value: phone).where.not(id: identifier.id).exists?
    def audit(outcome, old_phone: identifier.normalized_value, new_phone:, revoked_session_count: nil)
      SecurityEvent.create!(brand: session.brand, user: session.user, event_type: "auth.phone_change.#{outcome}", severity: outcome == "succeeded" ? :info : :warning, ip_address:, user_agent:, metadata: { old_identifier_last4: old_phone.last(4), new_identifier_last4: new_phone.last(4), revoked_session_count: }.compact)
    end
    def failure(error) = Result.new(false, error, 0)
  end
end
