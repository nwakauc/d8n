module Identity
  class PhoneOtpVerifier
    Result = Data.define(:success?, :error, :user, :session, :raw_token)
    AccessResult = Data.define(:allowed?, :record, :reason)

    MAX_ATTEMPTS = 5

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, phone:, code:, ip_address: nil, user_agent: nil, device_name: nil)
      @brand = brand
      @phone = phone
      @code = code
      @ip_address = ip_address
      @user_agent = user_agent
      @device_name = device_name
    end

    def call
      return failure(:brand_required) unless active_brand?

      identifier = PhoneNormalizer.call(phone)
      return failure(:invalid_phone, identifier:) if identifier.blank?

      challenge = latest_challenge(identifier)
      return failure(:invalid_code, identifier:) if challenge.blank?

      verify_locked_challenge(challenge, identifier)
    end

    private

    attr_reader :brand, :phone, :code, :ip_address, :user_agent, :device_name

    def latest_challenge(identifier)
      OtpChallenge.active
        .where(brand:, identifier:, kind: :phone_otp)
        .order(created_at: :desc)
        .first
    end

    def verify_locked_challenge(challenge, identifier)
      ActiveRecord::Base.transaction do
        challenge.lock!
        next failure(:invalid_code, identifier:) if challenge.consumed? || challenge.expired?
        next lock_challenge(challenge, identifier) if challenge.attempt_count >= MAX_ATTEMPTS
        next failed_code(challenge, identifier) unless challenge.code_matches?(code)

        verify_challenge(challenge, identifier)
      end
    end

    def failed_code(challenge, identifier)
      challenge.increment!(:attempt_count)
      result = challenge.attempt_count >= MAX_ATTEMPTS ? :locked : :failed

      record_auth_attempt(identifier:, result:)
      record_security_event(identifier:, event_type: "auth.phone_otp.#{result}", severity: :warning)

      Result.new(false, :invalid_code, nil, nil, nil)
    end

    def lock_challenge(challenge, identifier)
      challenge.consume!
      record_auth_attempt(identifier:, result: :locked)
      record_security_event(identifier:, event_type: "auth.phone_otp.locked", severity: :warning)

      Result.new(false, :invalid_code, nil, nil, nil)
    end

    def verify_challenge(challenge, identifier)
      identity_access = user_and_identifier(identifier)
      return deny_access(challenge, identifier, identity_access) unless identity_access.allowed?

      identity_identifier = identity_access.record
      user = identity_identifier.user
      credential_access = credential_for(user, identity_identifier)
      return deny_access(challenge, identifier, credential_access, user:, identity_identifier:) unless credential_access.allowed?

      credential = credential_access.record
      membership_access = brand_membership_for(user)
      return deny_access(challenge, identifier, membership_access, user:, identity_identifier:, credential:) unless membership_access.allowed?

      challenge.consume!
      raw_token, session = Session.issue!(user:, brand:, credential:, device_name:, ip_address:, user_agent:)
      record_auth_attempt(identifier:, result: :succeeded, user:, identity_identifier:, credential:)
      record_security_event(
        identifier:,
        event_type: "auth.phone_otp.succeeded",
        severity: :info,
        user:
      )

      Result.new(true, nil, user, session, raw_token)
    end

    def user_and_identifier(identifier)
      identity_identifier = IdentityIdentifier.kept.find_by(kind: :phone, normalized_value: identifier)
      if identity_identifier.present?
        return denied_access(:user_inactive, identity_identifier) unless active_record?(identity_identifier.user)

        return allowed_access(identity_identifier)
      end

      deleted_identifier = IdentityIdentifier.find_by(kind: :phone, normalized_value: identifier)
      return denied_access(:identity_inactive, deleted_identifier) if deleted_identifier.present?

      create_user_and_identifier(identifier)
    rescue ActiveRecord::RecordNotUnique
      identity_identifier = IdentityIdentifier.kept.find_by!(kind: :phone, normalized_value: identifier)
      return denied_access(:user_inactive, identity_identifier) unless active_record?(identity_identifier.user)

      allowed_access(identity_identifier)
    end

    def create_user_and_identifier(identifier)
      User.transaction(requires_new: true) do
        user = User.create!
        identity_identifier = user.identity_identifiers.create!(
          kind: :phone,
          normalized_value: identifier,
          verified_at: Time.current,
          last_seen_at: Time.current
        )

        allowed_access(identity_identifier)
      end
    end

    def credential_for(user, identity_identifier)
      credential = Credential.kept.find_by(user:, identity_identifier:, kind: :phone_otp)
      return denied_access(:credential_inactive, credential) if credential.present? && !credential.active?

      deleted_credential = Credential.find_by(user:, identity_identifier:, kind: :phone_otp)
      return denied_access(:credential_inactive, deleted_credential) if credential.nil? && deleted_credential.present?

      credential ||= Credential.create!(
        user:,
        identity_identifier:,
        kind: :phone_otp,
        status: :active,
        verified_at: Time.current
      )
      credential.update!(last_used_at: Time.current)
      allowed_access(credential)
    end

    def brand_membership_for(user)
      membership = BrandMembership.kept.find_by(user:, brand:)
      return denied_access(:membership_inactive, membership) if membership.present? && !membership.active?

      deleted_membership = BrandMembership.find_by(user:, brand:)
      return denied_access(:membership_inactive, deleted_membership) if membership.nil? && deleted_membership.present?

      membership ||= BrandMembership.create!(user:, brand:, status: :active)
      allowed_access(membership)
    end

    def deny_access(challenge, identifier, access, user: nil, identity_identifier: nil, credential: nil)
      identity_identifier ||= access.record if access.record.is_a?(IdentityIdentifier)
      credential ||= access.record if access.record.is_a?(Credential)
      user ||= identity_identifier&.user
      challenge.consume!
      record_auth_attempt(
        identifier:,
        result: :failed,
        user:,
        identity_identifier:,
        credential:
      )
      record_security_event(
        identifier:,
        event_type: "auth.phone_otp.denied",
        severity: :warning,
        user:,
        metadata: { reason: access.reason.to_s }
      )

      Result.new(false, :invalid_code, nil, nil, nil)
    end

    def allowed_access(record)
      AccessResult.new(true, record, nil)
    end

    def denied_access(reason, record = nil)
      AccessResult.new(false, record, reason)
    end

    def active_record?(record)
      record.deleted_at.nil? && record.active?
    end

    def active_brand?
      brand.present? && active_record?(brand)
    end

    def failure(error, identifier: nil)
      record_auth_attempt(identifier:, result: :failed) if identifier.present?
      Result.new(false, error, nil, nil, nil)
    end

    def record_auth_attempt(identifier:, result:, user: nil, identity_identifier: nil, credential: nil)
      AuthAttempt.create!(
        brand:,
        user:,
        identity_identifier:,
        credential:,
        kind: :phone_otp,
        result:,
        identifier:,
        ip_address:,
        user_agent:
      )
    end

    def record_security_event(identifier:, event_type:, severity:, user: nil, metadata: {})
      SecurityEvent.create!(
        brand:,
        user:,
        event_type:,
        severity:,
        ip_address:,
        user_agent:,
        metadata: {
          identifier_kind: "phone",
          identifier_last4: identifier.to_s.last(4)
        }.merge(metadata)
      )
    end
  end
end
