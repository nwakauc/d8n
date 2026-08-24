require "test_helper"

module D8n
  module Platform
    class CapabilityKeyTest < ActiveSupport::TestCase
      test "accepts stable dotted capability keys" do
        key = CapabilityKey.new("discovery.surface.daily_batch")

        assert_equal "discovery", key.namespace
        assert_equal "discovery.surface.daily_batch", key.to_s
        assert_equal key, CapabilityKey.new(key)
      end

      test "rejects malformed keys" do
        [ "", "discovery", "Discovery.feed", "discovery/find", "discovery..feed" ].each do |value|
          assert_raises(ArgumentError, value.inspect) { CapabilityKey.new(value) }
        end
      end

      test "rejects brand slugs in capability keys when composing a brand" do
        error = assert_raises(ArgumentError) do
          CapabilityKey.new("discovery.dateza_feed", reserved_segments: %w[dateza])
        end

        assert_equal "capability key must not contain a brand slug", error.message
      end
    end
  end
end
