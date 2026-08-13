module Identity
  class PasswordChange
    Result = Data.define(:success?, :error, :revoked_session_count, :retry_after)
    PURPOSE = "password_change"

    def self.call(...)
      new(...).call
    end

    def initialize(session:, current_password:, password:, password_confirmation:, ip_address: nil, user_agent: nil)
      @session = session
      @current_password = current_password
      @password = password
      @password_confirmation = password_confirmation
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure(:password_credential_required) unless eligible_credential?

      result = nil
      ActiveRecord::Base.transaction do
        AuthenticationLock.with_lock(
          brand: session.brand,
          purpose: PURPOSE,
          identifier: identifier.normalized_value,
          ip_address:
        ) do
          result = change_under_lock
        end
      end
      result
    end

    private

    attr_reader :session, :current_password, :password, :password_confirmation, :ip_address, :user_agent

    def change_under_lock
      throttle = PasswordThrottle.call(
        brand: session.brand,
        purpose: PURPOSE,
        identifier: identifier.normalized_value,
        ip_address:
      )
      if throttle.throttled?
        audit(result: :throttled, retry_after: throttle.retry_after)
        return failure(:rate_limited, retry_after: throttle.retry_after)
      end

      unless PasswordEngine.matches?(credential:, password: current_password)
        audit(result: :failed, failure_stage: "reauthentication")
        return failure(:invalid_current_password)
      end

      unless password == password_confirmation && PasswordEngine.valid?(password:)
        audit(result: :failed, failure_stage: "replacement")
        return failure(:invalid_password)
      end

      if PasswordEngine.matches?(credential:, password:)
        audit(result: :failed, failure_stage: "replacement")
        return failure(:password_unchanged)
      end

      PasswordEngine.set!(credential:, password:)
      revoked_count = revoke_other_credential_sessions
      audit(result: :succeeded, revoked_session_count: revoked_count)
      Result.new(true, nil, revoked_count, nil)
    end

    def revoke_other_credential_sessions
      Session.active.where(user: session.user, credential:)
        .where.not(id: session.id)
        .update_all(revoked_at: Time.current, updated_at: Time.current)
    end

    def eligible_credential?
      credential&.password? && credential.active? && credential.deleted_at.nil? &&
        identifier.present? && identifier.deleted_at.nil? && credential.user_id == session.user_id
    end

    def credential
      @credential ||= session.credential
    end

    def identifier
      @identifier ||= credential&.identity_identifier
    end

    def audit(result:, retry_after: nil, revoked_session_count: nil, failure_stage: nil)
      PasswordAudit.record!(
        brand: session.brand,
        purpose: PURPOSE,
        result:,
        identifier: identifier.normalized_value,
        identifier_kind: identifier.kind,
        ip_address:,
        user_agent:,
        user: session.user,
        identity_identifier: identifier,
        credential:,
        retry_after:,
        metadata: { revoked_session_count:, failure_stage: }.compact
      )
    end

    def failure(error, retry_after: nil)
      Result.new(false, error, 0, retry_after)
    end
  end
end
