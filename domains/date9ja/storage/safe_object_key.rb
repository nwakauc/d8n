# frozen_string_literal: true

require "pathname"

module Date9ja
  module Storage
    # The single accepted safe-key + path-containment contract for the Date9ja
    # media rehearsal (L2). Both the READ side (LocalCorpusReader) and the WRITE
    # side (SyntheticMedia::Generator) depend on it, so a key the reader refuses
    # can never be written, and vice versa.
    #
    # Grammar mirrors Date9ja::Storage::SourceReader: opaque S3-style keys —
    # `/`-joined conservative tokens, no absolute path, no `.`/`..` segments, no
    # backslash, control, whitespace, `?`, `#`, or `%` (encoded-traversal
    # ambiguity). Keys are never filesystem paths.
    module SafeObjectKey
      SEGMENT = /\A[A-Za-z0-9][A-Za-z0-9_=-]*\z/
      MAX_LENGTH = 512
      UNSAFE_CHARS = /[\x00-\x1f\x7f]|[?#\\%\s]/

      class InvalidKey < StandardError; end
      # A parent directory inside the corpus tree is a symlink that escapes root.
      class UnsafePath < StandardError; end

      module_function

      # @return [Boolean]
      def valid?(key)
        validate!(key)
        true
      rescue InvalidKey
        false
      end

      # @return [String] the key, unchanged, when it satisfies the contract.
      # @raise [InvalidKey]
      def validate!(key)
        value = key.to_s
        raise InvalidKey, "blank source object key" if value.empty?
        raise InvalidKey, "source object key too long" if value.bytesize > MAX_LENGTH
        raise InvalidKey, "source object key must not be absolute" if value.start_with?("/")
        raise InvalidKey, "source object key must not start with '.'" if value.start_with?(".")
        raise InvalidKey, "source object key has unsafe characters" if value.match?(UNSAFE_CHARS)

        segments = value.split("/", -1)
        if segments.any? { |s| s.empty? || s == "." || s == ".." }
          raise InvalidKey, "source object key has an empty or relative segment"
        end
        unless segments.all? { |s| s.match?(SEGMENT) }
          raise InvalidKey, "source object key segment is not the accepted grammar"
        end

        value
      end

      # Resolve a validated key to an absolute path that is PROVEN to sit strictly
      # under `root` (a directory Pathname). Returns nil for an invalid key, an
      # absent object, or any path-boundary / symlink escape. Read side.
      def resolve_within(root, key)
        return nil unless valid?(key)

        root_real = Pathname.new(root).realpath
        candidate = root_real.join(key)
        return nil unless candidate.exist?

        real = candidate.realpath
        return nil unless under?(root_real, real)

        real
      rescue Errno::ENOENT
        nil
      end

      # Absolute path to write `key` under `root`, creating intermediate
      # directories safely. Fails closed if the key is invalid or if any existing
      # ancestor inside the corpus tree is a symlink resolving outside root, or if
      # the resolved parent is not strictly under root. Write side.
      #
      # @raise [InvalidKey, UnsafePath]
      def write_path_within(root, key)
        validate!(key)
        root_real = Pathname.new(root).realpath
        rel = Pathname.new(key)
        parent_rel = rel.dirname

        current = root_real
        parent_rel.descend do |segment|
          next if segment.to_s == "."

          current = current.join(segment.basename)
          if current.symlink?
            resolved = current.realpath
            raise UnsafePath, "corpus path component is a symlink outside root" unless under?(root_real, resolved)

            current = resolved
          elsif !current.exist?
            current.mkdir
          elsif !current.directory?
            raise UnsafePath, "corpus path component is not a directory"
          end
        end

        target = current.join(rel.basename)
        unless under?(root_real, current) && (under?(root_real, target) || target == root_real)
          raise UnsafePath, "resolved write path escapes the corpus root"
        end

        target
      end

      def under?(root_real, path)
        root_s = root_real.to_s
        path_s = path.to_s
        path_s == root_s || path_s.start_with?("#{root_s}/")
      end
    end
  end
end
