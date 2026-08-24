module D8n
  module Platform
    class DiscoverySurface
      DELIVERY_TYPES = %i[feed browse restricted_pool daily_batch].freeze

      attr_reader :key, :delivery_type, :strategy, :policy, :eligibility_policy, :facets, :exclusions,
        :decorators, :allocation, :error_code

      def initialize(
        key:,
        delivery_type:,
        strategy: nil,
        policy: nil,
        eligibility_policy:,
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
        @eligibility_policy = eligibility_policy
        @facets = immutable_items(facets)
        @exclusions = immutable_items(exclusions)
        @decorators = immutable_items(decorators)
        @allocation = allocation&.freeze
        @error_code = error_code.to_sym

        raise ArgumentError, "surface key must use the discovery namespace" unless @key.namespace == "discovery"
        raise ArgumentError, "unsupported discovery delivery type" unless DELIVERY_TYPES.include?(@delivery_type)
        unless @eligibility_policy.is_a?(Matching::EligibilityPolicy)
          raise ArgumentError, "surface eligibility policy is required"
        end
        validate_facets!
        validate_allocation!

        freeze
      end

      def delivery_capability_key
        CapabilityKey.new("discovery.surface.#{delivery_type}")
      end

      private

      def immutable_items(items)
        Array(items).map { |item| item.is_a?(Hash) ? item.dup.freeze : item }.freeze
      end

      def validate_facets!
        parameters = facets.map do |facet|
          raise ArgumentError, "facet definition is required" unless facet.is_a?(Hash)

          type = facet.fetch(:type).to_sym
          raise ArgumentError, "unsupported facet type" unless %i[activity option_group].include?(type)
          raise ArgumentError, "option-group facet requires a group" if type == :option_group && facet[:option_group].blank?

          facet.fetch(:parameter).to_s.presence || raise(ArgumentError, "facet parameter is required")
        end
        raise ArgumentError, "duplicate facet parameter" unless parameters.uniq.length == parameters.length
      end

      def validate_allocation!
        if delivery_type == :daily_batch
          unless allocation.is_a?(StableDailyAllocationPolicy)
            raise ArgumentError, "daily batch surface requires a stable daily allocation policy"
          end
          unless strategy&.respond_to?(:rank_daily_selection)
            raise ArgumentError, "daily batch surface requires an allocation ranking strategy"
          end
        elsif allocation.present?
          raise ArgumentError, "allocation policy is only supported by a daily batch surface"
        end
      end
    end
  end
end
