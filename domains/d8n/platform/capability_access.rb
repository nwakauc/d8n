module D8n
  module Platform
    class CapabilityAccess
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
        raise NotConfigured, contract.error_code_for(key)
      end
    end
  end
end
