# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Storage
    class SafeObjectKeyTest < ActiveSupport::TestCase
      setup do
        @root = Pathname.new(Dir.mktmpdir("sok-test")).realpath
      end

      teardown { FileUtils.remove_entry(@root) }

      SAFE = [ "abc", "snapshot/1/4f1ac30dcdf2af8efcf44f77e8196d1e", "a/b/c-d_e=f" ].freeze

      def unsafe_keys
        {
          "blank" => "",
          "absolute" => "/etc/passwd",
          "leading dot" => ".ssh/key",
          "parent segment" => "a/../../x",
          "bare parent" => "../x",
          "empty segment" => "a//b",
          "backslash" => "a\\..\\x",
          "percent encoded" => "a/%2e%2e/x",
          "query" => "a?b",
          "fragment" => "a#b",
          "whitespace" => "a b/c",
          "tab" => "a\tb",
          "control char" => "a\x01b",
          "null byte" => "a\x00b",
          "bad grammar" => "a/@b/c",
          "too long" => "a/#{'x' * 600}"
        }
      end

      test "accepts the conservative storage-key grammar" do
        SAFE.each { |k| assert SafeObjectKey.valid?(k), k.inspect }
      end

      test "rejects every unsafe key shape" do
        unsafe_keys.each do |label, key|
          refute SafeObjectKey.valid?(key), "expected #{label} rejected"
          assert_raises(SafeObjectKey::InvalidKey) { SafeObjectKey.validate!(key) }
        end
      end

      test "write_path_within returns a path strictly under root and creates dirs" do
        path = SafeObjectKey.write_path_within(@root, "snapshot/1/obj")

        assert path.to_s.start_with?("#{@root}/")
        assert path.dirname.directory?
        File.binwrite(path, "x")
        assert_equal path, SafeObjectKey.resolve_within(@root, "snapshot/1/obj")
      end

      test "write_path_within refuses an unsafe key before any directory is made" do
        assert_raises(SafeObjectKey::InvalidKey) { SafeObjectKey.write_path_within(@root, "a/../../x") }
        assert_empty @root.children
      end

      test "write_path_within refuses a symlinked corpus component escaping root" do
        outside = Pathname.new(Dir.mktmpdir("sok-outside"))
        (@root / "snapshot").mkpath
        File.symlink(outside, @root / "snapshot" / "evil")

        assert_raises(SafeObjectKey::UnsafePath) { SafeObjectKey.write_path_within(@root, "snapshot/evil/obj") }
        refute (outside / "obj").exist?
      ensure
        FileUtils.remove_entry(outside)
      end

      test "resolve_within refuses a symlink target outside root" do
        outside = Pathname.new(Dir.mktmpdir("sok-outside2"))
        File.write(outside / "secret", "s")
        (@root / "d").mkpath
        File.symlink(outside / "secret", @root / "d" / "leak")

        assert_nil SafeObjectKey.resolve_within(@root, "d/leak")
      ensure
        FileUtils.remove_entry(outside)
      end
    end
  end
end
