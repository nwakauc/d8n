module D8n
  module Platform
    module Capabilities
      module Discovery
        DEFINITIONS = [
          CapabilityDefinition.new(key: "discovery.surface.feed", status: :available,
            implementations: %w[Matching::Discovery]),
          CapabilityDefinition.new(key: "discovery.surface.browse", status: :available,
            implementations: %w[Matching::Find::Search]),
          CapabilityDefinition.new(key: "discovery.surface.restricted_pool", status: :available,
            implementations: %w[HookTonight::Discovery], dependencies: %w[discovery.surface.feed]),
          CapabilityDefinition.new(key: "discovery.surface.daily_batch", status: :available,
            implementations: %w[Matching::StableDailySelection DiscoveryAllocation DiscoveryAllocationCandidate]),
          CapabilityDefinition.new(key: "discovery.facet.activity", status: :available,
            implementations: %w[Matching::FacetFilter]),
          CapabilityDefinition.new(key: "discovery.facet.option_group", status: :available,
            implementations: %w[Matching::FacetFilter]),
          CapabilityDefinition.new(key: "discovery.exposure", status: :available,
            implementations: %w[Matching::Find::Search FindProfileExposure]),
          CapabilityDefinition.new(key: "discovery.cursor", status: :available,
            implementations: %w[Matching::Cursor Matching::Find::Cursor]),
          CapabilityDefinition.new(key: "discovery.decoration", status: :available,
            implementations: %w[D8n::Platform::ResponseDecorations])
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
