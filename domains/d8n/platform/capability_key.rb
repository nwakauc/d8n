module D8n
  module Platform
    class CapabilityKey
      FORMAT = /\A[a-z][a-z0-9]*(?:\.[a-z][a-z0-9_]*)+\z/

      attr_reader :value

      def initialize(value, reserved_segments: [])
        @value = value.to_s
        segments = @value.split(".")
        tokens = segments.flat_map { |segment| segment.split("_") }

        raise ArgumentError, "invalid capability key" unless FORMAT.match?(@value)
        if (tokens & Array(reserved_segments).map(&:to_s)).any?
          raise ArgumentError, "capability key must not contain a brand slug"
        end

        freeze
      end

      def namespace
        value.split(".").first
      end

      def to_s
        value
      end

      def ==(other)
        other.is_a?(CapabilityKey) && other.value == value
      end
      alias eql? ==

      def hash
        value.hash
      end
    end
  end
end
