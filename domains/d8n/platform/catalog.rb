module D8n
  module Platform
    module Catalog
      CAPABILITY_MODULES = [
        Capabilities::Id,
        Capabilities::Profile,
        Capabilities::Discovery,
        Capabilities::Verify,
        Capabilities::Match,
        Capabilities::Chat,
        Capabilities::Trust,
        Capabilities::Media,
        Capabilities::Notify,
        Capabilities::Pay,
        Capabilities::Ai,
        Capabilities::Insights,
        Capabilities::Admin
      ].freeze

      DEFINITIONS = CAPABILITY_MODULES.flat_map(&:definitions).freeze
      BY_KEY = DEFINITIONS.index_by { |definition| definition.key.to_s }.freeze

      def self.definitions
        DEFINITIONS
      end

      def self.fetch(key)
        BY_KEY.fetch(CapabilityKey.new(key).to_s)
      end

      def self.key?(key)
        BY_KEY.key?(CapabilityKey.new(key).to_s)
      rescue ArgumentError
        false
      end

      def self.validate!(brand_slugs: [])
        raise ArgumentError, "duplicate capability keys" unless BY_KEY.size == DEFINITIONS.size

        definitions.each do |definition|
          CapabilityKey.new(definition.key, reserved_segments: brand_slugs)
          definition.dependencies.each { |dependency| fetch(dependency) }
        end

        true
      end
    end
  end
end
