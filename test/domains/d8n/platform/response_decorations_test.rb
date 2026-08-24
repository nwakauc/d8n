require "test_helper"

module D8n
  module Platform
    class ResponseDecorationsTest < ActiveSupport::TestCase
      test "bulk-merges only fields contributed by configured decorators" do
        profiles = [ Struct.new(:id).new(1), Struct.new(:id).new(2) ]
        first = lambda do |viewer:, profiles:|
          assert_equal :viewer, viewer
          profiles.to_h { |profile| [ profile.id, { first: profile.id } ] }
        end
        second = lambda do |viewer:, profiles:|
          assert_equal :viewer, viewer
          { profiles.first.id => { second: true } }
        end

        payloads = ResponseDecorations.call(
          viewer: :viewer, profiles:, decorators: [ first, second ]
        )

        assert_equal({ first: 1, second: true }, payloads.fetch(1))
        assert_equal({ first: 2 }, payloads.fetch(2))
        assert_equal({ 1 => {}, 2 => {} }, ResponseDecorations.call(viewer: :viewer, profiles:, decorators: []))
      end
    end
  end
end
