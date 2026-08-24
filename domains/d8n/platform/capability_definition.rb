module D8n
  module Platform
    class CapabilityDefinition
      STATUSES = %i[available partial planned].freeze

      attr_reader :key, :status, :implementations, :dependencies, :brand_configurable, :limitations

      def initialize(
        key:,
        status:,
        implementations: [],
        dependencies: [],
        brand_configurable: true,
        limitations: nil
      )
        @key = CapabilityKey.new(key)
        @status = status.to_sym
        @implementations = Array(implementations).map(&:to_s).freeze
        @dependencies = Array(dependencies).map { |dependency| CapabilityKey.new(dependency) }.freeze
        @brand_configurable = !!brand_configurable
        @limitations = limitations&.to_s

        raise ArgumentError, "invalid capability status" unless STATUSES.include?(@status)
        raise ArgumentError, "available capability requires an implementation" if available? && @implementations.empty?

        freeze
      end

      def available?
        status == :available
      end

      def partial?
        status == :partial
      end

      def planned?
        status == :planned
      end
    end
  end
end
