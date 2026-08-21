module Matching
  module Find
    class PolicyRegistry
      class UnsupportedBrand < StandardError; end

      POLICIES = {
        "dateza" => Policies::Dateza
      }.freeze

      def self.fetch(brand:)
        POLICIES.fetch(brand.slug) do
          raise UnsupportedBrand, "Find is not configured for this brand"
        end
      end
    end
  end
end
