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
          CapabilityDefinition.new(key: "discovery.surface.daily_batch", status: :planned),
          CapabilityDefinition.new(key: "discovery.facet.activity", status: :available,
            implementations: %w[Matching::FacetFilter]),
          CapabilityDefinition.new(key: "discovery.facet.option_group", status: :partial,
            implementations: %w[Matching::FacetFilter],
            limitations: "The current universal filter still hardcodes the HookUs vibes group."),
          CapabilityDefinition.new(key: "discovery.exposure", status: :available,
            implementations: %w[Matching::Find::Search FindProfileExposure]),
          CapabilityDefinition.new(key: "discovery.cursor", status: :available,
            implementations: %w[Matching::Cursor Matching::Find::Cursor]),
          CapabilityDefinition.new(key: "discovery.decoration", status: :partial,
            implementations: %w[Matching::CandidateSerializer Profiles::StatusFields],
            limitations: "Optional Hook state is not yet composed by brand and surface.")
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
