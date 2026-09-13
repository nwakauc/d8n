module D8n
  module Platform
    module Capabilities
      module Community
        DEFINITIONS = [
          CapabilityDefinition.new(
            key: "community.read",
            status: :available,
            implementations: %w[Community::Serializer CommunityQuestion CommunityEvent CommunityStory CommunityCircle]
          ),
          CapabilityDefinition.new(
            key: "community.participation",
            status: :available,
            implementations: %w[Community::Submissions Community::Rsvp Community::Membership],
            dependencies: %w[community.read]
          ),
          CapabilityDefinition.new(
            key: "community.moderation",
            status: :available,
            implementations: %w[Community::Moderation Admin::AuthorizationContext],
            dependencies: %w[community.read]
          ),
          CapabilityDefinition.new(key: "community.story_video", status: :planned)
        ].freeze
        def self.definitions = DEFINITIONS
      end
    end
  end
end
