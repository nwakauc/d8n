# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Snapshot
    class VideoSourceTest < ActiveSupport::TestCase
      FakeConnection = Struct.new(:behaviour) do
        def execute(_sql)
          raise ActiveRecord::StatementInvalid, "PG::RaiseException: SCHEMA DRIFT: x" if behaviour == :drift

          true
        end

        def exec_query(_sql)
          ActiveRecord::Result.new([], [])
        end
      end

      test "requires videos: or connection:" do
        assert_raises(ArgumentError) { VideoSource.new }
      end

      test "yields VideoRecords in deterministic primary-key order" do
        videos = [ { "id" => 3 }, { "id" => 1 }, { "id" => 2 } ].map { |r| base_video.merge(r) }
        records = VideoSource.new(videos: videos, attachments: [], blobs: []).to_a

        assert_equal %w[1 2 3], records.map(&:source_id)
        assert(records.all? { |r| r.is_a?(VideoRecord) })
      end

      test "owner_source_id is the legacy user_id" do
        record = VideoSource.new(videos: [ base_video.merge("id" => 1, "user_id" => 77) ]).to_a.sole
        assert_equal "77", record.owner_source_id
      end

      test "links only ProfileVideo/video attachments and their blob integrity metadata" do
        source = VideoSource.new(
          videos: [ base_video.merge("id" => 1) ],
          attachments: [
            { "id" => 10, "name" => "video", "record_type" => "ProfileVideo", "record_id" => 1, "blob_id" => 90 },
            { "id" => 11, "name" => "video", "record_type" => "Message", "record_id" => 1, "blob_id" => 91 },
            { "id" => 12, "name" => "poster", "record_type" => "ProfileVideo", "record_id" => 1, "blob_id" => 92 }
          ],
          blobs: [ { "id" => 90, "byte_size" => 10, "checksum" => "c", "content_type" => "video/mp4" } ]
        )
        record = source.to_a.sole

        assert_equal 1, record.attachments.size
        assert_equal "90", record.attachments.first.blob.source_id
        assert_equal "video/mp4", record.attachments.first.blob.content_type
      end

      test "the SELECT column lists never name the storage locator, filename or rejection_reason" do
        forbidden = %w[key filename metadata service_name rejection_reason]
        assert_empty(VideoSource::BLOB_COLUMNS & forbidden)
        assert_empty(VideoSource::VIDEO_COLUMNS & forbidden)
        assert_empty(VideoSource::ATTACHMENT_COLUMNS & forbidden)
        assert_empty(VideoRecord.members.map(&:to_s) & forbidden)
        assert_empty(BlobRecord.members.map(&:to_s) & forbidden)
      end

      test "runs the schema guard before reading rows when given a connection" do
        source = VideoSource.new(connection: FakeConnection.new(:drift))
        assert_raises(SchemaGuard::SchemaDriftError) { source.to_a }
      end

      test "skips the schema guard for synthetic rows" do
        assert_nothing_raised { VideoSource.new(videos: [ base_video ]).to_a }
      end

      private

      def base_video
        {
          "id" => 1, "user_id" => 1, "duration_seconds" => nil, "moderation_status" => 0,
          "created_at" => nil, "reviewed_at" => nil
        }
      end
    end
  end
end
