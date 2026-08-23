module Hooks
  # Explicit product enablement for the Hook route family. Route presence is not
  # capability: a brand must be listed here before any Hook/Hook Tonight surface
  # reaches profile authorization or mutation logic.
  class CapabilityPolicy
    ENABLED = {
      "hookus" => %i[hook hook_tonight].freeze
    }.freeze
    ERROR_CODES = {
      hook: :hook_not_configured,
      hook_tonight: :hook_tonight_not_configured
    }.freeze

    class UnsupportedBrand < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    def self.authorize!(brand:, capability:)
      return if ENABLED.fetch(brand.slug, []).include?(capability)

      raise UnsupportedBrand, ERROR_CODES.fetch(capability)
    end
  end
end
