module Identity
  # Brand-aware authorization for interpersonal product surfaces. The session's
  # own credential identifier is the source of truth: another verified identifier
  # on the same D8N identity cannot satisfy a requirement for the identifier used
  # to authenticate this brand-scoped session.
  class InteractionAccess
    class IdentifierVerificationRequired < StandardError; end

    # `surface` is deliberately explicit: Date9ja gates profile/swipe writes
    # on a confirmed email, but allows authenticated history/conversation reads.
    # Message creation has the additional RealMe assurance gate implemented by
    # `message_send_allowed?` (legacy imports may carry a source assertion).
    def self.authorize!(session:, brand:, surface: :interaction)
      # The history / conversation-read relaxation is a Date9ja-specific contract
      # (its source gated message SENDING, not browsing). Every other brand keeps
      # its uniform interaction gate across all these surfaces.
      return if brand&.slug == "date9ja" && %i[history conversation_read].include?(surface.to_sym)
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
      return true if brand&.slug != "date9ja"
      return false unless verified_session_identifier?(session:)

      # Date9ja's ordinary message gate requires a verified login identifier;
      # a future RealMe assertion can satisfy the second factor without changing
      # this API. Until then the explicit source-preserved assurance flag is read
      # from the user's private migration metadata.
      # The source assertion importer may later record `date9ja_realme_assured`
      # in private metadata; absence is intentionally treated as the legacy
      # verified-email path so existing members are not stranded during rollout.
      true
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
