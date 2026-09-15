module D8n
  module Platform
    module Capabilities
      module Verify
        DEFINITIONS = [
          CapabilityDefinition.new(key: "verify.contact.email", status: :available,
            implementations: %w[Identity::VerificationRequester Identity::VerificationVerifier]),
          CapabilityDefinition.new(key: "verify.contact.phone", status: :available,
            implementations: %w[Identity::VerificationRequester Identity::VerificationVerifier]),
          # Manual-review RealMe v1 (ADR 0034): a member submits evidence, a
          # human admin approves/rejects/requests resubmission. No automated
          # face-match or document-match yet — those stay :planned.
          CapabilityDefinition.new(key: "verify.identity.selfie", status: :available,
            implementations: %w[Identity::RealmeSubmission Trust::ModerateRealmeVerification]),
          CapabilityDefinition.new(key: "verify.identity.liveness", status: :available,
            implementations: %w[Identity::RealmeSubmission Trust::ModerateRealmeVerification]),
          CapabilityDefinition.new(key: "verify.identity.document", status: :available,
            implementations: %w[Identity::RealmeSubmission Trust::ModerateRealmeVerification]),
          CapabilityDefinition.new(key: "verify.identity.face_match", status: :planned),
          CapabilityDefinition.new(key: "verify.level", status: :planned)
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
