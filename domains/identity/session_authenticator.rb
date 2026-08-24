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

      session = Session.includes(:user, :credential).find_by(token_digest: Session.digest_token(token))
      return Result.new(false, nil, nil, :invalid_token) if session.blank?
      return Result.new(false, nil, nil, :wrong_brand) if session.brand_id != brand.id
      return Result.new(false, nil, nil, :revoked_session) if session.revoked?
      return Result.new(false, nil, nil, :expired_session) if session.expired?
      return Result.new(false, nil, nil, :invalid_token) unless active_record?(brand)
      return Result.new(false, nil, nil, :invalid_token) unless active_record?(session.user)
      return Result.new(false, nil, nil, :invalid_token) unless active_membership?(session)
      return Result.new(false, nil, nil, :invalid_token) unless active_credential?(session)

      session.update!(last_used_at: Time.current)
      Result.new(true, session, session.user, nil)
    end

    private

    attr_reader :brand, :token

    def active_record?(record)
      record.active? && record.deleted_at.nil?
    end

    def active_membership?(session)
      BrandMembership.kept.active.exists?(user_id: session.user_id, brand_id: session.brand_id)
    end

    def active_credential?(session)
      session.credential.nil? || active_record?(session.credential)
    end
  end
end
