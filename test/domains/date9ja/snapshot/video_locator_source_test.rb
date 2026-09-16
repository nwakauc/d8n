# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Snapshot
    class VideoLocatorSourceTest < ActiveSupport::TestCase
      test "resolves a known blob id to its locator" do
        src = VideoLocatorSource.new(rows: {
          "10" => { key: "abc123", service_name: "cloudflare" }
        })
        locator = src.call("10")
        assert_equal "abc123", locator.key
        assert_equal "cloudflare", locator.service_name
      end

      test "returns nil for an unknown blob id" do
        assert_nil VideoLocatorSource.new(rows: {}).call("999")
      end

      test "fails closed on a key that violates the opaque-object-key grammar" do
        src = VideoLocatorSource.new(rows: {
          "1" => { key: "../../etc/passwd", service_name: "cloudflare" },
          "2" => { key: "/absolute/path", service_name: "cloudflare" },
          "3" => { key: "has space", service_name: "cloudflare" }
        })
        assert_nil src.call("1")
        assert_nil src.call("2")
        assert_nil src.call("3")
      end

      test "service_names lists distinct services in scope" do
        src = VideoLocatorSource.new(rows: {
          "1" => { key: "a", service_name: "cloudflare" },
          "2" => { key: "b", service_name: "cloudflare" },
          "3" => { key: "c", service_name: "amazon" }
        })
        assert_equal %w[amazon cloudflare], src.service_names.sort
      end

      test "requires connection: or rows:" do
        assert_raises(ArgumentError) { VideoLocatorSource.new }
      end

      test "the connection SELECT is a narrow allowlist filtered to ProfileVideo/video" do
        # Guard against a future edit widening the query.
        sql_source = File.read(Rails.root.join("domains/date9ja/snapshot/video_locator_source.rb"))
        assert_equal "ProfileVideo", VideoLocatorSource::VIDEO_RECORD_TYPE
        assert_equal "video", VideoLocatorSource::VIDEO_ATTACHMENT_NAME
        select_line = sql_source[/exec_query\(.*?\)/m].to_s
        assert_includes select_line, "SELECT b.id, b.key, b.service_name"
        assert_includes select_line, "record_type = '\#{VIDEO_RECORD_TYPE}' AND a.name = '\#{VIDEO_ATTACHMENT_NAME}'"
        assert_includes select_line, "ORDER BY b.id"
        refute_includes select_line, "filename"
        refute_includes select_line.downcase, "metadata"
      end
    end
  end
end
