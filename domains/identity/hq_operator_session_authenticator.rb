module Identity
  class HqOperatorSessionAuthenticator
    Result = Data.define(:success?, :session, :user, :error)

    def self.call(token:)
      return Result.new(false, nil, nil, :missing_token) if token.blank?

      session = HqOperatorSession.includes(:user, :admin_user, :admin_mfa_credential)
        .find_by(token_digest: HqOperatorSession.digest_token(token))
      return Result.new(false, nil, nil, :invalid_token) if session.blank?
      return Result.new(false, nil, nil, :revoked_session) if session.revoked?
      return Result.new(false, nil, nil, :expired_session) if session.expired?
      return Result.new(false, nil, nil, :invalid_token) unless session.user.active? && session.user.deleted_at.nil?
      return Result.new(false, nil, nil, :invalid_token) unless session.admin_user.active? && session.admin_user.deleted_at.nil?

      session.update!(last_used_at: Time.current)
      Result.new(true, session, session.user, nil)
    end
  end
end
