# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Storage
    class SourceReaderTest < ActiveSupport::TestCase
      # In-memory transport double. Only head / get_stream exist — mirrors the
      # reader surface (no put/delete/copy).
      class FakeTransport
        def initialize(objects: {}, redirect: false, boom: false)
          @objects = objects
          @redirect = redirect
          @boom = boom
          @seen = []
        end

        attr_reader :seen

        def head(url)
          @seen << [ :head, url ]
          return [ 302, { "location" => "https://evil.example" } ] if @redirect
          raise "provider blew up: secret-bucket/deadbeefkey" if @boom

          bytes = @objects[key_of(url)]
          return [ 404, {} ] if bytes.nil?

          [ 200, { "content-length" => bytes.bytesize.to_s } ]
        end

        def get_stream(url, chunk_size:)
          @seen << [ :get, url ]
          return 302 if @redirect

          bytes = @objects[key_of(url)]
          return 404 if bytes.nil?

          bytes.b.each_char.each_slice(chunk_size).each { |slice| yield slice.join }
          200
        end

        private

        def key_of(url) = url.split("/", 5).last
      end

      def reader(transport)
        SourceReader.new(account_id: "acct123", bucket: "date9ja-media", transport:)
      end

      test "constructs the endpoint from the account id and hits the right URL" do
        transport = FakeTransport.new(objects: { "k" => "x" })
        reader(transport).head("k")
        assert_equal [ [ :head, "https://acct123.r2.cloudflarestorage.com/date9ja-media/k" ] ], transport.seen
      end

      test "a caller-supplied endpoint/host is rejected" do
        %i[endpoint url host uri origin].each do |field|
          assert_raises(SourceReader::EndpointRejected) do
            SourceReader.from_config(account_id: "a", bucket: "b", transport: FakeTransport.new,
              field => "https://attacker.example")
          end
        end
      end

      test "non-https / off-allowlist host is rejected at construction" do
        assert_raises(SourceReader::EndpointRejected) do
          SourceReader.new(account_id: "", bucket: "b", transport: FakeTransport.new)
        end
      end

      test "redirects are refused, never followed" do
        assert_raises(SourceReader::RedirectRefused) { reader(FakeTransport.new(redirect: true)).head("k") }
      end

      test "there is no write/delete/copy surface" do
        r = reader(FakeTransport.new)
        %i[put upload delete destroy copy write].each do |m|
          refute r.respond_to?(m), "SourceReader must not expose ##{m}"
        end
      end

      test "missing object returns nil from head" do
        assert_nil reader(FakeTransport.new(objects: {})).head("absent")
      end

      test "download streams into the io and returns the byte count" do
        io = StringIO.new
        n = reader(FakeTransport.new(objects: { "k" => "abcdef" * 10 })).download("k", io:, byte_ceiling: 1_000)
        assert_equal 60, n
        assert_equal "abcdef" * 10, io.string
      end

      test "download aborts past the byte ceiling" do
        io = StringIO.new
        assert_raises(SourceReader::ByteCeilingExceeded) do
          reader(FakeTransport.new(objects: { "k" => "x" * 5_000 })).download("k", io:, byte_ceiling: 1_000, chunk_size: 256)
        end
      end

      test "source key grammar: rejects traversal, control chars, and transport-unsafe chars" do
        r = reader(FakeTransport.new)
        [
          "/etc/passwd", "a/../../b", "a/./b", "..", "a//b", "",
          "a\x00b", "a\tb", "a b", "a?b", "a#b", "a\\b", "a%2e%2e/b", "a%2Fb"
        ].each do |bad|
          assert_raises(SourceReader::InvalidKey, "should reject #{bad.inspect}") { r.head(bad) }
        end
      end

      test "source key grammar: accepts the known Date9ja key shapes" do
        objs = { "abc123DEF456" => "x", "abc123/variants/thumb_x" => "x", "k_1_2" => "x", "a=b-c" => "x" }
        r = reader(FakeTransport.new(objects: objs))
        objs.each_key { |k| assert r.head(k), "should accept #{k.inspect}" }
      end

      test "provider exceptions are redacted (no bucket/key/url leaks)" do
        error = assert_raises(SourceReader::ObjectUnavailable) { reader(FakeTransport.new(boom: true)).head("k") }
        refute_match(/secret-bucket|deadbeefkey/, error.message)
      end
    end
  end
end
