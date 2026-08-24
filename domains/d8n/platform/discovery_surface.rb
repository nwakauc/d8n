module D8n
  module Platform
    class DiscoverySurface
      DELIVERY_TYPES = %i[feed browse restricted_pool daily_batch].freeze

      attr_reader :key, :delivery_type, :strategy, :policy, :facets, :exclusions,
        :decorators, :allocation, :error_code

      def initialize(
        key:,
        delivery_type:,
        strategy: nil,
        policy: nil,
        facets: [],
        exclusions: [],
        decorators: [],
        allocation: nil,
        error_code:
      )
        @key = CapabilityKey.new(key)
        @delivery_type = delivery_type.to_sym
        @strategy = strategy
        @policy = policy
        @facets = immutable_items(facets)
        @exclusions = immutable_items(exclusions)
        @decorators = immutable_items(decorators)
        @allocation = allocation&.freeze
        @error_code = error_code.to_sym

        raise ArgumentError, "surface key must use the discovery namespace" unless @key.namespace == "discovery"
        raise ArgumentError, "unsupported discovery delivery type" unless DELIVERY_TYPES.include?(@delivery_type)

        freeze
      end

      def delivery_capability_key
        CapabilityKey.new("discovery.surface.#{delivery_type}")
      end

      private

      def immutable_items(items)
        Array(items).map { |item| item.is_a?(Hash) ? item.dup.freeze : item }.freeze
      end
    end
  end
end
