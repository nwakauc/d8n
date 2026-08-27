module Identity
  # Explicit, credential-verified reactivation of a deactivated BrandMembership
  # (see Accounts::DeactivateAccount). Deliberately mirrors PasswordLogin rather
  # than exposing a bare "reactivate" button on a stale session — deactivation
  # revokes every session for the brand, so restoring access requires proving the
  # password again. This is the "explicit reactivation confirmation" the account
  # lifecycle calls for, without inventing a second confirmation mechanism.
  #
  # Reuses PasswordLogin's throttle/audit purpose: this is still fundamentally a
  # credential-verification attempt against the same identifier, and giving it a
  # separate throttle bucket would let an attacker double their guess budget by
  # alternating between /login and /reactivation.
  class AccountReactivation
    Result = Data.define(:success?, :error, :user, :credential, :session, :raw_token, :retry_after)
    PURPOSE = PasswordLogin::PURPOSE

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

      reactivate(login_identifier)
    end

    private

    attr_reader :brand, :identifier_input, :password, :device_name, :ip_address, :user_agent

    def reactivate(login_identifier)
      result = nil

      ActiveRecord::Base.transaction do
        AuthenticationLock.with_lock(
          brand:, purpose: PURPOSE, identifier: login_identifier.normalized_value, ip_address:
        ) do
          throttle = PasswordThrottle.call(
            brand:, purpose: PURPOSE, identifier: login_identifier.normalized_value, ip_address:
          )
          result = if throttle.throttled?
            audit(login_identifier, result: :throttled, retry_after: throttle.retry_after)
            failure(:rate_limited, retry_after: throttle.retry_after)
          else
            reactivate_unthrottled(login_identifier)
          end
        end
      end

      result
    end

    def reactivate_unthrottled(login_identifier)
      identifiers = IdentityIdentifier.kept.where(
        kind: login_identifier.kind,
        normalized_value: login_identifier.lookup_values
      ).limit(2).to_a
      identity_identifier = identifiers.one? ? identifiers.first : nil
      user = identity_identifier&.user
      credential = identity_identifier&.credentials&.kept&.find_by(kind: :password)
      password_matches = credential.present? ? PasswordEngine.matches?(credential:, password:) : PasswordEngine.burn(password:)

      unless password_matches && active_record?(user) && active_record?(credential)
        audit(login_identifier, result: :failed, user:, identity_identifier:, credential:)
        return failure(:invalid_credentials)
      end

      # Only reachable after a correct password, so revealing "not deactivated"
      # here (vs. the generic invalid_credentials above) cannot be used to
      # enumerate account state without already knowing the password.
      membership = BrandMembership.lock.find_by(user:, brand:)
      unless membership.present? && membership.deleted_at.nil? && membership.deactivated?
        audit(login_identifier, result: :failed, user:, identity_identifier:, credential:)
        return failure(:account_not_deactivated)
      end

      membership.update!(status: :active)
      raw_token, session = Session.issue!(
        user:, brand:, credential:, device_name:, ip_address:, user_agent:
      )
      identity_identifier.update!(last_seen_at: Time.current)
      credential.update!(last_used_at: Time.current)
      record_event(brand:, user:, membership:)
      audit(login_identifier, result: :succeeded, user:, identity_identifier:, credential:)

      Result.new(true, nil, user, credential, session, raw_token, nil)
    end

    def invalid_credentials
      PasswordEngine.burn(password:)
      audit(nil, result: :failed)
      failure(:invalid_credentials)
    end

    def record_event(brand:, user:, membership:)
      SecurityEvent.create!(
        brand:, user:,
        event_type: "account.reactivated", severity: :info,
        metadata: { brand_membership_id: membership.id }
      )
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

    def failure(error, retry_after: nil)
      Result.new(false, error, nil, nil, nil, nil, retry_after)
    end
  end
end
