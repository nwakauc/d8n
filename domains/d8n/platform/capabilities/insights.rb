module D8n
  module Platform
    module Capabilities
      module Insights
        DEFINITIONS = %w[
          insights.acquisition
          insights.activation
          insights.engagement
          insights.marketplace_health
          insights.retention
          insights.safety
          insights.revenue
        ].map { |key| CapabilityDefinition.new(key:, status: :planned) }.freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
