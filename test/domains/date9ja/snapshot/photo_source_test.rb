# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Snapshot
    class PhotoSourceTest < ActiveSupport::TestCase
      FakeConnection = Struct.new(:behaviour) do
        def execute(_sql)
          raise ActiveRecord::StatementInvalid, "PG::RaiseException: SCHEMA DRIFT: x" if behaviour == :drift

          true
        end

        def exec_query(_sql)
          ActiveRecord::Result.new([], [])
        end
      end

      test "requires photos: or connection:" do
        assert_raises(ArgumentError) { PhotoSource.new }
      end

      test "yields PhotoRecords in deterministic primary-key order" do
        photos = [ { "id" => 3 }, { "id" => 1 }, { "id" => 2 } ].map { |r| base_photo.merge(r) }
        records = PhotoSource.new(photos: photos, attachments: [], blobs: []).to_a

        assert_equal %w[1 2 3], records.map(&:source_id)
        assert(records.all? { |r| r.is_a?(PhotoRecord) })
      end

      test "links only Photo/image attachments and their blob integrity metadata" do
        source = PhotoSource.new(
          photos: [ base_photo.merge("id" => 1) ],
          attachments: [
            { "id" => 10, "name" => "image", "record_type" => "Photo", "record_id" => 1, "blob_id" => 90 },
            { "id" => 11, "name" => "image", "record_type" => "Message", "record_id" => 1, "blob_id" => 91 },
            { "id" => 12, "name" => "avatar", "record_type" => "Photo", "record_id" => 1, "blob_id" => 92 }
          ],
          blobs: [ { "id" => 90, "byte_size" => 10, "checksum" => "c", "content_type" => "image/png" } ]
        )
        record = source.to_a.sole

        assert_equal 1, record.attachments.size
        assert_equal "90", record.attachments.first.blob.source_id
        assert_equal "image/png", record.attachments.first.blob.content_type
      end

      test "the SELECT column lists never name the storage locator or filename" do
        forbidden = %w[key filename metadata service_name]
        assert_empty(PhotoSource::BLOB_COLUMNS & forbidden)
        assert_empty(PhotoSource::PHOTO_COLUMNS & forbidden)
        assert_empty(PhotoSource::ATTACHMENT_COLUMNS & forbidden)
        assert_empty(PhotoRecord.members.map(&:to_s) & forbidden)
        assert_empty(BlobRecord.members.map(&:to_s) & forbidden)
      end

      test "runs the schema guard before reading rows when given a connection" do
        source = PhotoSource.new(connection: FakeConnection.new(:drift))
        assert_raises(SchemaGuard::SchemaDriftError) { source.to_a }
      end

      test "skips the schema guard for synthetic rows" do
        assert_nothing_raised { PhotoSource.new(photos: [ base_photo ]).to_a }
      end

      private

      def base_photo
        {
          "id" => 1, "user_id" => 1, "position" => 0, "moderation_status" => 1,
          "is_primary" => false, "created_at" => nil, "reviewed_at" => nil
        }
      end
    end
  end
end
