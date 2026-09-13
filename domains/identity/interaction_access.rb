module Identity
  # Brand-aware authorization for interpersonal product surfaces. The session's
  # own credential identifier is the source of truth: another verified identifier
  # on the same D8N identity cannot satisfy a requirement for the identifier used
  # to authenticate this brand-scoped session.
  class InteractionAccess
    class IdentifierVerificationRequired < StandardError; end

    REALME_ASSERTION_TYPES = %w[selfie video liveness government_id gov_id].freeze

    def self.authorize!(session:, brand:, surface: :interaction)
      return unless verification_requirement(brand:) == :verified_login_identifier
      # Existing profile/onboarding/lifecycle authorization remains authoritative
      # when the member is not yet published. This policy only adds a gate for a
      # valid, published member (DateZA; Date9ja) whose sole missing step is
      # verifying the identifier they logged in with.
      return unless published_profile?(session:, brand:)
      return if verified_session_identifier?(session:)

      raise IdentifierVerificationRequired
    end

    def self.message_send_allowed?(session:, brand:)
      return true unless message_send_verification_requirement(brand:) == :verified_realme_method
      return false if session.blank? || brand.blank?

      verified_phone?(session:, brand:) || approved_realme_assertion?(session:, brand:)
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

    def self.verified_phone?(session:, brand:)
      return false unless phone_verification_enabled?(brand:)

      IdentityIdentifier.kept.phone.where(user_id: session.user_id).where.not(verified_at: nil).exists?
    end
    private_class_method :verified_phone?

    def self.approved_realme_assertion?(session:, brand:)
      VerificationAssertion.where(
        brand_id: brand.id,
        user_id: session.user_id,
        status: "approved",
        check_type: realme_assertion_types(brand:)
      ).exists?
    end
    private_class_method :approved_realme_assertion?

    def self.realme_assertion_types(brand:)
      return REALME_ASSERTION_TYPES unless phone_verification_enabled?(brand:)

      [ "phone", *REALME_ASSERTION_TYPES ]
    end
    private_class_method :realme_assertion_types

    def self.phone_verification_enabled?(brand:)
      D8n::Platform::BrandRegistry.fetch(brand:).capability_enabled?("verify.contact.phone")
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      false
    end
    private_class_method :phone_verification_enabled?

    def self.verification_requirement(brand:)
      D8n::Platform::BrandRegistry.fetch(brand:).interaction.verification_requirement
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      nil
    end
    private_class_method :verification_requirement

    def self.message_send_verification_requirement(brand:)
      D8n::Platform::BrandRegistry.fetch(brand:).interaction.message_send_verification_requirement
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      nil
    end
    private_class_method :message_send_verification_requirement
  end
end
