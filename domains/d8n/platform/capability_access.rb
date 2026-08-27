module D8n
  module Platform
    class CapabilityAccess
      DEFAULT_ERROR_CODES = {
        "discovery.surface.feed" => :matching_not_configured,
        "discovery.surface.browse" => :find_not_configured,
        "match.interaction.like" => :matching_not_configured,
        "match.interaction.pass" => :matching_not_configured,
        "match.relationship.list" => :matching_not_configured,
        "match.relationship.unmatch" => :matching_not_configured,
        "match.hook" => :hook_not_configured,
        "match.hook_tonight" => :hook_tonight_not_configured,
        "chat.conversation" => :messaging_not_configured,
        "chat.message.text" => :messaging_not_configured
      }.freeze

      class NotConfigured < StandardError
        attr_reader :code

        def initialize(code)
          @code = code.to_sym
          super(@code.to_s)
        end
      end

      def self.authorize!(contract:, capability:, surface: nil)
        if surface
          return contract.surface(surface) if contract.capability_enabled?(capability) && contract.surface_enabled?(surface)
        elsif contract.capability_enabled?(capability)
          return true
        end

        key = surface || capability
        raise NotConfigured, configured_error_code(contract:, key:, capability:)
      end

      def self.configured_error_code(contract:, key:, capability:)
        contract.error_codes.fetch(key.to_s) do
          contract.error_codes.fetch(capability.to_s) do
            DEFAULT_ERROR_CODES.fetch(capability.to_s, :capability_not_configured)
          end
        end
      end
      private_class_method :configured_error_code
    end
  end
end
