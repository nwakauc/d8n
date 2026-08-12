module Identity
  class SessionAuthenticator
    Result = Data.define(:success?, :session, :user, :error)

    def self.call(...)
      new(...).call
    end

    def initialize(brand:, token:)
      @brand = brand
      @token = token
    end

    def call
      return Result.new(false, nil, nil, :brand_required) if brand.blank?
      return Result.new(false, nil, nil, :missing_token) if token.blank?

      session = Session.includes(:user).find_by(token_digest: Session.digest_token(token))
      return Result.new(false, nil, nil, :invalid_token) if session.blank?
      return Result.new(false, nil, nil, :invalid_token) if session.brand_id != brand.id
      return Result.new(false, nil, nil, :invalid_token) if session.revoked? || session.expired?

      session.update!(last_used_at: Time.current)
      Result.new(true, session, session.user, nil)
    end

    private

    attr_reader :brand, :token
  end
end
