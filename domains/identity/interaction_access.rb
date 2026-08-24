module Identity
  # Brand-aware authorization for interpersonal product surfaces. The session's
  # own credential identifier is the source of truth: another verified identifier
  # on the same D8N identity cannot satisfy a requirement for the identifier used
  # to authenticate this brand-scoped session.
  class InteractionAccess
    class IdentifierVerificationRequired < StandardError; end

    def self.authorize!(session:, brand:)
      return unless verification_requirement(brand:) == :verified_login_identifier
      # Existing profile/onboarding/lifecycle authorization remains authoritative
      # when the member is not yet published. This policy only changes the valid,
      # published DateZA member case where verification is the sole missing gate.
      return unless published_profile?(session:, brand:)
      return if verified_session_identifier?(session:)

      raise IdentifierVerificationRequired
    end

    def self.published_profile?(session:, brand:)
      return false if session.blank? || brand.blank?

      Profile.kept.active.visible.exists?(user_id: session.user_id, brand_id: brand.id)
    end
    private_class_method :published_profile?

    def self.verified_session_identifier?(session:)
      credential = session.credential
      identifier = credential&.identity_identifier

      credential&.user_id == session.user_id && identifier&.user_id == session.user_id &&
        identifier.deleted_at.nil? && identifier.verified_at.present?
    end
    private_class_method :verified_session_identifier?

    def self.verification_requirement(brand:)
      D8n::Platform::BrandRegistry.fetch(brand:).interaction.verification_requirement
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      nil
    end
    private_class_method :verification_requirement
  end
end
