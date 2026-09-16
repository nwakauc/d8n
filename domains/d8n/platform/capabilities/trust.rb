module D8n
  module Platform
    module Capabilities
      module Trust
        DEFINITIONS = [
          CapabilityDefinition.new(key: "trust.block", status: :available,
            implementations: %w[Trust::BlockProfile Trust::UnblockProfile Trust::BlockPolicy]),
          CapabilityDefinition.new(key: "trust.report", status: :available,
            implementations: %w[Trust::FileReport Trust::ReportTargets]),
          CapabilityDefinition.new(key: "trust.report_evidence", status: :available,
            implementations: %w[Trust::FileReport Trust::ReportTargets Report]),
          CapabilityDefinition.new(key: "trust.moderation_queue", status: :available,
            implementations: %w[Admin::ReportQueue Admin::ReportDetail]),
          CapabilityDefinition.new(key: "trust.profile_suspension", status: :available,
            implementations: %w[Admin::SuspendProfile Admin::ReinstateProfile]),
          CapabilityDefinition.new(key: "trust.enforcement_audit", status: :available,
            implementations: %w[Admin::EnforcementAudit]),
          CapabilityDefinition.new(key: "trust.reputation", status: :planned),
          CapabilityDefinition.new(key: "trust.fraud_detection", status: :planned),
          # ADR 0025: brand-scoped, idempotent, rebuildable ledger + a
          # score-plus-explanation read surface. Live point emission into
          # existing flows (verification/photos/profile completion) is
          # deliberately not part of this — historical replay only so far.
          CapabilityDefinition.new(key: "trust.trust_score", status: :available,
            implementations: %w[Trust::Ledger Api::V1::TrustScoresController])
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
