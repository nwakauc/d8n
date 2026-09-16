# frozen_string_literal: true

module Date9ja
  module Snapshot
    # Deterministic reader over the Date9ja `profile_videos` table and their
    # single authoritative Active Storage attachment (`record_type = 'ProfileVideo'`,
    # `name = 'video'`), plus the linked blob's integrity metadata.
    #
    #   VideoSource.new(connection: Date9ja::Snapshot::Connection.connect!)
    #   VideoSource.new(videos: [...], attachments: [...], blobs: [...])  # tests
    #
    # SELECT lists name only the columns pass 1 may read. The legacy storage
    # locator (`active_storage_blobs.key`), `filename`, `metadata`, `service_name`
    # and the free-text `rejection_reason` are NEVER selected — pass 1 does not
    # need them and pass 2 re-reads the locator through the controlled
    # source-storage adapter (Date9ja::Snapshot::MediaLocatorSource).
    class VideoSource
      include Enumerable

      VIDEO_COLUMNS = %w[id user_id duration_seconds moderation_status created_at reviewed_at].freeze
      ATTACHMENT_COLUMNS = %w[id name record_type record_id blob_id].freeze
      BLOB_COLUMNS = %w[id byte_size checksum content_type].freeze

      VIDEO_RECORD_TYPE = "ProfileVideo"
      VIDEO_ATTACHMENT_NAME = "video"

      def initialize(videos: nil, attachments: [], blobs: [], connection: nil, verify_schema: true)
        raise ArgumentError, "provide videos: or connection:" if videos.nil? && connection.nil?

        @videos = videos
        @attachments = attachments
        @blobs = blobs
        @connection = connection
        @verify_schema = verify_schema
      end

      def each
        return enum_for(:each) unless block_given?

        SchemaGuard.verify!(connection: @connection) if @connection && @verify_schema

        blobs_by_id = blob_rows.to_h { |row| [ row.fetch("id").to_s, BlobRecord.from_raw(row) ] }
        attachments_by_record = attachment_rows
          .select { |row| row["record_type"] == VIDEO_RECORD_TYPE && row["name"] == VIDEO_ATTACHMENT_NAME }
          .group_by { |row| row.fetch("record_id").to_s }

        video_rows.each do |row|
          attachments = (attachments_by_record[row.fetch("id").to_s] || [])
            .sort_by { |a| a.fetch("id").to_i }
            .map { |a| AttachmentRecord.from_raw(a, blob: blobs_by_id[a["blob_id"].to_s]) }

          yield VideoRecord.from_raw(row, attachments:)
        end
      end

      private

      def video_rows
        rows =
          if @videos
            @videos.map { |row| row.transform_keys(&:to_s) }
          else
            @connection.exec_query("SELECT #{VIDEO_COLUMNS.join(', ')} FROM profile_videos ORDER BY id").to_a
          end
        rows.sort_by { |row| row.fetch("id").to_i }
      end

      def attachment_rows
        return @attachments.map { |row| row.transform_keys(&:to_s) } if @videos

        @connection.exec_query(
          "SELECT #{ATTACHMENT_COLUMNS.map { |c| "a.#{c}" }.join(', ')} " \
          "FROM active_storage_attachments a " \
          "WHERE a.record_type = '#{VIDEO_RECORD_TYPE}' AND a.name = '#{VIDEO_ATTACHMENT_NAME}' " \
          "ORDER BY a.record_id, a.id"
        ).to_a
      end

      def blob_rows
        return @blobs.map { |row| row.transform_keys(&:to_s) } if @videos

        @connection.exec_query(
          "SELECT #{BLOB_COLUMNS.map { |c| "b.#{c}" }.join(', ')} " \
          "FROM active_storage_blobs b " \
          "JOIN active_storage_attachments a ON a.blob_id = b.id " \
          "WHERE a.record_type = '#{VIDEO_RECORD_TYPE}' AND a.name = '#{VIDEO_ATTACHMENT_NAME}'"
        ).to_a
      end
    end
  end
end
