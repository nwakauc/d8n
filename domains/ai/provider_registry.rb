module Ai
  # Provider selection is intentionally process configuration, never a request
  # parameter or a brand-controlled value. A brand may enable an assistant, but
  # cannot redirect its members' private prompts to an arbitrary endpoint.
  module ProviderRegistry
    class ConfigurationError < StandardError; end

    def self.build
      case ENV.fetch("D8N_AI_PROVIDER", "disabled")
      when "openai" then Providers::Openai.new
      when "disabled" then Providers::Disabled.new
      else raise ConfigurationError, "unsupported D8N AI provider"
      end
    end
  end
end
