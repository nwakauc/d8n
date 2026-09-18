require "digest"
require "tempfile"

module Migration
  # Only attested objects; no overwrite/delete. Existing bytes require SHA-256.
  class ManifestMediaTransfer
    class InvalidManifest < StandardError; end
    KINDS = %w[photo video message_attachment verification_evidence].freeze

    def initialize(source:, destination:, source_bucket:, destination_bucket:)
      @source, @destination = source, destination
      @source_bucket, @destination_bucket = source_bucket, destination_bucket
    end

    def call(manifest)
      validate!(manifest)
      counts = { required: manifest.fetch("objects").size, transferred: 0, verified_existing: 0, failed: 0 }
      manifest.fetch("objects").each do |entry|
        counts[transfer(entry) == :existing ? :verified_existing : :transferred] += 1
      rescue StandardError
        counts[:failed] += 1 # No keys/URLs/provider exception payloads in reports.
      end
      counts
    end

    private

    def validate!(manifest)
      unless manifest["version"] == 1 && manifest["brand"] == "date9ja" && manifest["objects"].is_a?(Array)
        raise InvalidManifest, "invalid_manifest"
      end
      seen = {}
      manifest.fetch("objects").each do |entry|
        valid = KINDS.include?(entry["kind"]) && entry["source_id"].is_a?(String) && entry["source_id"].present? &&
          %w[source_key destination_key].all? { |field| entry[field].is_a?(String) && entry[field].present? } &&
          entry["byte_size"].is_a?(Integer) && entry["byte_size"].positive? &&
          entry["sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
        raise InvalidManifest, "invalid_object_attestation" unless valid
        raise InvalidManifest, "duplicate_destination_key" if seen[entry["destination_key"]]

        seen[entry["destination_key"]] = true
      end
    end

    def transfer(entry)
      begin
        @destination.head_object(bucket: @destination_bucket, key: entry.fetch("destination_key"))
        verify(@destination, @destination_bucket, entry.fetch("destination_key"), entry)
        return :existing
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
        # Only a missing-object response permits creation.
      end
      Tempfile.create("date9ja-owned-media") do |io|
        io.binmode
        verify(@source, @source_bucket, entry.fetch("source_key"), entry, output: io)
        io.flush
        io.rewind
        @destination.put_object(bucket: @destination_bucket, key: entry.fetch("destination_key"), body: io,
          if_none_match: "*")
        verify(@destination, @destination_bucket, entry.fetch("destination_key"), entry)
      end
      :transferred
    end

    def verify(client, bucket, key, entry, output: nil)
      digest = Digest::SHA256.new
      size = 0
      client.get_object(bucket:, key:) do |chunk|
        size += chunk.bytesize
        raise InvalidManifest, "oversized_object" if size > entry.fetch("byte_size")

        digest.update(chunk)
        output&.write(chunk)
      end
      unless size == entry.fetch("byte_size") && digest.hexdigest == entry.fetch("sha256")
        raise InvalidManifest, "object_integrity_mismatch"
      end
    end
  end
end
