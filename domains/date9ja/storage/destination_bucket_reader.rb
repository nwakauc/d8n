# frozen_string_literal: true

module Date9ja
  module Storage
    # Read path for Pass 2 (Migration::MediaTransfer / Date9ja::Import::PhotoTransfer
    # / VideoTransfer) when the source bytes have ALREADY been copied into the
    # D8N-controlled destination bucket under the exact legacy object key
    # (PRODUCTION-CUTOVER-RUNBOOK.md section 0.B, Path B1 -- a plain
    # bucket-to-bucket byte copy, done once, out of band, by
    # scripts/date9ja/transfer_media_bytes.rb). Drop-in for
    # Date9ja::Storage::SourceReader on the read path: same observable
    # contract (head/download, missing-object errors, bounded reads) as
    # Date9ja::Storage::LocalCorpusReader, but backed by real R2 instead of
    # a local synthetic corpus. Read-only: no write/delete/copy method
    # exists on this class.
    class DestinationBucketReader
      def initialize(client:, bucket:)
        @client = client
        @bucket = bucket
      end

      # @return [Hash] { byte_size: Integer } or nil when the object is absent.
      def head(key)
        response = client.head_object(bucket: bucket, key: key)
        { byte_size: response.content_length }
      rescue Aws::S3::Errors::NotFound
        nil
      end

      # Streams the object into `io`, aborting mid-stream past `byte_ceiling`.
      # @return [Integer] bytes written.
      def download(key, io:, byte_ceiling:, chunk_size: 5 * 1024 * 1024)
        io.truncate(0) if io.respond_to?(:truncate)
        io.rewind if io.respond_to?(:rewind)
        written = 0

        begin
          client.get_object(bucket: bucket, key: key) do |chunk|
            written += chunk.bytesize
            if written > byte_ceiling
              raise SourceReader::ByteCeilingExceeded, "source object exceeds the transfer ceiling"
            end

            io.write(chunk)
          end
        rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
          raise SourceReader::ObjectUnavailable, "source object unavailable"
        end

        io.flush if io.respond_to?(:flush)
        written
      end

      private

      attr_reader :client, :bucket
    end
  end
end
