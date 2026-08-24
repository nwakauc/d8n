module D8n
  module Platform
    module Capabilities
      module Verify
        DEFINITIONS = [
          CapabilityDefinition.new(key: "verify.contact.email", status: :available,
            implementations: %w[Identity::VerificationRequester Identity::VerificationVerifier]),
          CapabilityDefinition.new(key: "verify.contact.phone", status: :available,
            implementations: %w[Identity::VerificationRequester Identity::VerificationVerifier]),
          CapabilityDefinition.new(key: "verify.identity.selfie", status: :planned),
          CapabilityDefinition.new(key: "verify.identity.liveness", status: :planned),
          CapabilityDefinition.new(key: "verify.identity.face_match", status: :planned),
          CapabilityDefinition.new(key: "verify.identity.document", status: :planned),
          CapabilityDefinition.new(key: "verify.level", status: :planned)
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
