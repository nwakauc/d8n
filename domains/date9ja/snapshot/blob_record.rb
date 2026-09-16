# frozen_string_literal: true

module Date9ja
  module Snapshot
    # `active_storage_blobs` integrity metadata only — never the key, filename,
    # service_name or free-text metadata.
    BlobRecord = Data.define(:id, :byte_size, :checksum, :content_type) do
      def self.from_raw(raw)
        row = raw.transform_keys(&:to_s)
        new(
          id: row["id"],
          byte_size: row["byte_size"],
          checksum: row["checksum"],
          content_type: row["content_type"]
        )
      end

      def source_id = id.to_s
    end
  end
end
