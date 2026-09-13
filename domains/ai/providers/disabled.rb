module Ai
  module Providers
    class Disabled
      def complete(**)
        raise Ai::ProviderUnavailable, "AI provider is unavailable"
      end
    end
  end
end
