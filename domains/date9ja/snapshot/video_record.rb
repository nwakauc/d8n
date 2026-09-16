# frozen_string_literal: true

module Date9ja
  module Snapshot
    # One Date9ja `profile_videos` row plus its authoritative `video` attachment(s).
    #
    # The legacy table is keyed 1:1 on `user_id` (UNIQUE index), has no
    # `deleted_at` column (no soft-delete), no ordering column and no
    # `is_primary` — a member has at most one introduction video.
    VideoRecord = Data.define(
      :id, :user_id, :duration_seconds, :moderation_status, :created_at,
      :reviewed_at, :attachments
    ) do
      def self.from_raw(raw, attachments:)
        row = raw.transform_keys(&:to_s)
        new(
          id: row["id"],
          user_id: row["user_id"],
          duration_seconds: row["duration_seconds"],
          moderation_status: row["moderation_status"],
          created_at: row["created_at"],
          reviewed_at: row["reviewed_at"],
          attachments: attachments
        )
      end

      def source_id = id.to_s

      def owner_source_id = user_id.to_s

      def video_attachment = attachments.first
    end
  end
end
