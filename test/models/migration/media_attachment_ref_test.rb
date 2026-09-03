# frozen_string_literal: true

require "test_helper"

module Migration
  class MediaAttachmentRefTest < ActiveSupport::TestCase
    setup do
      @object, = MediaObjectRef.preflight!(
        source_system: "date9ja", source_blob_id: "10", checksum: "c", byte_size: 1, content_type: "image/jpeg",
        importer_version: "v1"
      )
      @other_object, = MediaObjectRef.preflight!(
        source_system: "date9ja", source_blob_id: "11", checksum: "c2", byte_size: 2, content_type: "image/png",
        importer_version: "v1"
      )
    end

    def record(**overrides)
      MediaAttachmentRef.record!(
        **{
          source_system: "date9ja", source_attachment_id: "500", media_object_ref: @object,
          source_record_entity: "photo", source_record_id: "42", attachment_name: "image",
          importer_version: "v1"
        }.merge(overrides)
      )
    end

    test "first record creates the row keyed on (source_system, source_attachment_id)" do
      ref, state = record
      assert_equal :created, state
      assert_equal @object.id, ref.media_object_ref_id
      assert ref.preflight_preflighted?
    end

    test "identical rerun is a no-op" do
      record
      assert_no_difference -> { MediaAttachmentRef.count } do
        _ref, state = record
        assert_equal :unchanged, state
      end
    end

    test "drift in the blob, source record, or name fails closed" do
      record
      assert_raises(MediaAttachmentRef::Drift) { record(media_object_ref: @other_object) }
      assert_raises(MediaAttachmentRef::Drift) { record(source_record_id: "999") }
      assert_raises(MediaAttachmentRef::Drift) { record(attachment_name: "avatar") }
    end

    test "one blob can back many attachments (blob reuse)" do
      record(source_attachment_id: "500")
      record(source_attachment_id: "501", source_record_id: "43")

      assert_equal 2, @object.media_attachment_refs.count
    end

    test "a destroyed object with attachments is protected" do
      record
      assert_raises(ActiveRecord::DeleteRestrictionError) { @object.destroy }
    end
  end
end
