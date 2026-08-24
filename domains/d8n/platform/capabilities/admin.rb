module D8n
  module Platform
    module Capabilities
      module Admin
        DEFINITIONS = [
          CapabilityDefinition.new(key: "admin.operator_authorization", status: :available,
            implementations: %w[Admin::ModeratorContext AdminAssignment AdminRole]),
          CapabilityDefinition.new(key: "admin.report_review", status: :available,
            implementations: %w[Admin::ReportQueue Admin::ReportDetail Admin::TransitionReport]),
          CapabilityDefinition.new(key: "admin.enforcement", status: :available,
            implementations: %w[Admin::SuspendProfile Admin::ReinstateProfile]),
          CapabilityDefinition.new(key: "admin.verification_review", status: :planned),
          CapabilityDefinition.new(key: "admin.user_operations", status: :planned),
          CapabilityDefinition.new(key: "admin.brand_operations", status: :planned),
          CapabilityDefinition.new(key: "admin.billing_operations", status: :planned),
          CapabilityDefinition.new(key: "admin.analytics", status: :planned)
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
