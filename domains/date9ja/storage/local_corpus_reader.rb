# frozen_string_literal: true

require "pathname"

module Date9ja
  module Storage
    # Rehearsal-only (L2) source transport over the LOCAL synthetic media corpus
    # (Date9ja::Snapshot::SyntheticMedia). Drop-in for Date9ja::Storage::SourceReader
    # on the Pass 2 read path: same observable contract — locate by exact source
    # key, stream bytes, bounded reads, missing-object errors, no redirects — but
    # it never touches the network, R2, or any credential.
    #
    # It reuses SourceReader's error classes so callers (Migration::MediaTransfer)
    # catch exactly the same exceptions. Key validation + path containment is the
    # shared Date9ja::Storage::SafeObjectKey contract — the same one the
    # synthetic-media generator writes through.
    class LocalCorpusReader
      def initialize(corpus_dir:)
        root = Pathname.new(corpus_dir)
        objects = root.join("objects")
        @root = (objects.directory? ? objects : root).realpath
      end

      # @return [Hash] { byte_size: Integer } or nil when the object is absent.
      def head(key)
        path = resolve(key)
        return nil unless path&.file?

        { byte_size: path.size }
      end

      # Streams the object into `io`, aborting mid-stream past `byte_ceiling`.
      # @return [Integer] bytes written.
      def download(key, io:, byte_ceiling:, chunk_size: 5 * 1024 * 1024)
        path = resolve(key)
        raise SourceReader::ObjectUnavailable, "source object unavailable" unless path&.file?

        io.truncate(0) if io.respond_to?(:truncate)
        io.rewind if io.respond_to?(:rewind)
        written = 0
        File.open(path, "rb") do |file|
          while (chunk = file.read(chunk_size))
            written += chunk.bytesize
            if written > byte_ceiling
              raise SourceReader::ByteCeilingExceeded, "source object exceeds the transfer ceiling"
            end

            io.write(chunk)
          end
        end
        io.flush if io.respond_to?(:flush)
        written
      end

      private

      def resolve(key)
        SafeObjectKey.resolve_within(@root, key)
      end
    end
  end
end
