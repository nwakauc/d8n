# frozen_string_literal: true

module Date9ja
  module Snapshot
    # One Date9ja `photos` row plus its authoritative image attachment(s).
    PhotoRecord = Data.define(
      :id, :user_id, :position, :moderation_status, :is_primary, :created_at,
      :reviewed_at, :attachments
    ) do
      def self.from_raw(raw, attachments:)
        row = raw.transform_keys(&:to_s)
        new(
          id: row["id"],
          user_id: row["user_id"],
          position: row["position"],
          moderation_status: row["moderation_status"],
          is_primary: ActiveModel::Type::Boolean.new.cast(row["is_primary"]) || false,
          created_at: row["created_at"],
          reviewed_at: row["reviewed_at"],
          attachments: attachments
        )
      end

      def source_id = id.to_s

      def owner_source_id = user_id.to_s

      def image_attachment = attachments.first
    end
  end
end
