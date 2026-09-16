# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Storage
    class LocalCorpusReaderTest < ActiveSupport::TestCase
      setup do
        @dir = Dir.mktmpdir("corpus-test")
        FileUtils.mkdir_p(File.join(@dir, "objects", "snapshot", "1"))
        @key = "snapshot/1/abcdef0123"
        @bytes = SecureRandom.bytes(4_096)
        File.binwrite(File.join(@dir, "objects", @key), @bytes)
        @reader = LocalCorpusReader.new(corpus_dir: @dir)
      end

      teardown { FileUtils.remove_entry(@dir) }

      test "head returns byte_size for a present object and nil for an absent one" do
        assert_equal({ byte_size: 4_096 }, @reader.head(@key))
        assert_nil @reader.head("snapshot/1/missing")
      end

      test "download streams the exact bytes into io" do
        io = StringIO.new
        written = @reader.download(@key, io:, byte_ceiling: 1.megabyte)

        assert_equal 4_096, written
        assert_equal @bytes, io.string.b
      end

      test "download fails closed past the byte ceiling" do
        io = StringIO.new
        assert_raises(SourceReader::ByteCeilingExceeded) do
          @reader.download(@key, io:, byte_ceiling: 100, chunk_size: 64)
        end
      end

      test "download raises ObjectUnavailable for a missing key" do
        assert_raises(SourceReader::ObjectUnavailable) do
          @reader.download("snapshot/1/nope", io: StringIO.new, byte_ceiling: 1.megabyte)
        end
      end

      test "path traversal and unsafe keys are rejected (treated as absent)" do
        [ "../secret", "/etc/passwd", "snapshot/../../x", "snapshot/./1", "a b", "a?b", "a%2e%2e" ].each do |bad|
          assert_nil @reader.head(bad), "expected #{bad.inspect} rejected"
          assert_raises(SourceReader::ObjectUnavailable) do
            @reader.download(bad, io: StringIO.new, byte_ceiling: 1.megabyte)
          end
        end
      end

      test "a symlink escaping the corpus root is refused" do
        outside = File.join(@dir, "outside.txt")
        File.write(outside, "secret")
        FileUtils.mkdir_p(File.join(@dir, "objects", "snapshot", "9"))
        File.symlink(outside, File.join(@dir, "objects", "snapshot", "9", "leak"))

        assert_nil @reader.head("snapshot/9/leak")
      end
    end
  end
end
