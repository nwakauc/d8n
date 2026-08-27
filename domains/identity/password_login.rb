module Identity
  class PasswordLogin
    Result = Data.define(:success?, :error, :user, :credential, :session, :raw_token, :retry_after)
    PURPOSE = "password_login"

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

      login_identifier = LoginIdentifier.call(identifier_input, brand:)
      return invalid_credentials unless login_identifier
      return failure(:auth_method_unavailable) unless AuthPolicy.enabled?(brand:, method: login_identifier.auth_method)

      authenticate(login_identifier)
    end

    private

    attr_reader :brand, :identifier_input, :password, :device_name, :ip_address, :user_agent

    def authenticate(login_identifier)
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
          result = if throttle.throttled?
            audit(login_identifier, result: :throttled, retry_after: throttle.retry_after)
            failure(:rate_limited, retry_after: throttle.retry_after)
          else
            authenticate_unthrottled(login_identifier)
          end
        end
      end

      result
    end

    def authenticate_unthrottled(login_identifier)
      identifiers = IdentityIdentifier.kept.where(
        kind: login_identifier.kind,
        normalized_value: login_identifier.lookup_values
      ).limit(2).to_a
      identity_identifier = identifiers.one? ? identifiers.first : nil
      user = identity_identifier&.user
      credential = identity_identifier&.credentials&.kept&.find_by(kind: :password)
      password_matches = credential.present? ? PasswordEngine.matches?(credential:, password:) : PasswordEngine.burn(password:)

      unless password_matches && active_record?(user) && active_record?(credential)
        audit(
          login_identifier,
          result: :failed,
          user:,
          identity_identifier:,
          credential:
        )
        return failure(:invalid_credentials)
      end

      membership = BrandMembership.kept.find_by(user:, brand:)
      # Reachable only after a correct password, so distinguishing "deactivated"
      # from the generic invalid_credentials below cannot be used to enumerate
      # account state without already knowing the password (see
      # Identity::AccountReactivation, which performs the actual reactivation).
      if membership&.deactivated?
        audit(login_identifier, result: :failed, user:, identity_identifier:, credential:)
        return failure(:account_deactivated)
      end

      unless active_membership?(membership)
        audit(
          login_identifier,
          result: :failed,
          user:,
          identity_identifier:,
          credential:
        )
        return failure(:invalid_credentials)
      end

      raw_token, session = Session.issue!(
        user:,
        brand:,
        credential:,
        device_name:,
        ip_address:,
        user_agent:
      )
      identity_identifier.update!(last_seen_at: Time.current)
      credential.update!(last_used_at: Time.current)
      audit(login_identifier, result: :succeeded, user:, identity_identifier:, credential:)

      Result.new(true, nil, user, credential, session, raw_token, nil)
    end

    def invalid_credentials
      PasswordEngine.burn(password:)
      audit(nil, result: :failed)
      failure(:invalid_credentials)
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
      active_record?(brand)
    end

    def active_record?(record)
      record.present? && record.active? && record.deleted_at.nil?
    end

    def active_membership?(membership)
      membership.present? && membership.active? && membership.deleted_at.nil?
    end

    def failure(error, retry_after: nil)
      Result.new(false, error, nil, nil, nil, nil, retry_after)
    end
  end
end
