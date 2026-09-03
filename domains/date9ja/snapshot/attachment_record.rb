# frozen_string_literal: true

module Date9ja
  module Snapshot
    # One `active_storage_attachments` row for a Photo image, with its blob's
    # integrity metadata (or nil when the blob row is missing).
    AttachmentRecord = Data.define(:id, :blob_id, :name, :record_type, :record_id, :blob) do
      def self.from_raw(raw, blob:)
        row = raw.transform_keys(&:to_s)
        new(
          id: row["id"], blob_id: row["blob_id"], name: row["name"],
          record_type: row["record_type"], record_id: row["record_id"], blob: blob
        )
      end

      def source_id = id.to_s
    end
  end
end
