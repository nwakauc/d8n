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
        "dateza" => Brands::Dateza,
        "date9ja" => Brands::Date9ja
      }.freeze

      def self.fetch(brand:)
        if Current.brand.equal?(brand) && Current.platform_contract
          return Current.platform_contract
        end

        provider = CONTRACTS[brand&.slug]
        raise UnsupportedBrand unless provider

        contract = provider.contract(brand:)
        Current.platform_contract = contract if Current.brand.equal?(brand)
        contract
      end

      def self.slugs
        CONTRACTS.keys
      end
    end
  end
end
