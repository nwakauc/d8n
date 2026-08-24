module D8n
  module Platform
    module BrandRegistry
      class UnsupportedBrand < StandardError
        attr_reader :code

        def initialize
          @code = :brand_not_configured
          super(@code.to_s)
        end
      end

      CONTRACTS = {
        "hookus" => Brands::Hookus,
        "dateza" => Brands::Dateza
      }.freeze

      def self.fetch(brand:)
        provider = CONTRACTS[brand&.slug]
        raise UnsupportedBrand unless provider

        provider.contract(brand:)
      end

      def self.slugs
        CONTRACTS.keys
      end
    end
  end
end
