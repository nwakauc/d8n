# frozen_string_literal: true

require "test_helper"

module Migration
  class MediaObjectRefTest < ActiveSupport::TestCase
    def preflight(**overrides)
      MediaObjectRef.preflight!(
        **{
          source_system: "date9ja", source_blob_id: "10",
          checksum: "abc123", byte_size: 204_800, content_type: "image/jpeg",
          importer_version: "date9ja-photo-preflight-v1"
        }.merge(overrides)
      )
    end

    test "first preflight creates the row keyed on (source_system, source_blob_id)" do
      ref, state = preflight

      assert_equal :created, state
      assert_equal "date9ja", ref.source_system
      assert_equal "10", ref.source_blob_id
      assert ref.preflight_preflighted?
      assert ref.transfer_not_started?
    end

    test "an identical rerun is a no-op" do
      preflight
      assert_no_difference -> { MediaObjectRef.count } do
        ref, state = preflight
        assert_equal :unchanged, state
        assert ref.persisted?
      end
    end

    test "integrity drift fails closed" do
      preflight
      assert_raises(MediaObjectRef::Drift) { preflight(checksum: "different") }
      assert_raises(MediaObjectRef::Drift) { preflight(byte_size: 999) }
      assert_raises(MediaObjectRef::Drift) { preflight(content_type: "image/png") }
    end

    test "the same source_blob_id under a different source_system is a separate object" do
      preflight(source_system: "date9ja")
      ref, state = preflight(source_system: "hookus")

      assert_equal :created, state
      assert_equal 2, MediaObjectRef.where(source_blob_id: "10").count
      assert_not_equal ref.source_system, "date9ja"
    end

    test "checksums are integrity metadata, not identity — matching checksums are not merged" do
      a, = preflight(source_blob_id: "1", checksum: "same")
      b, = preflight(source_blob_id: "2", checksum: "same")

      assert_not_equal a.id, b.id
    end

    test "missing or zero byte size cannot be recorded as a successful preflight" do
      assert_raises(ActiveRecord::RecordInvalid) { preflight(byte_size: 0) }
      assert_raises(ActiveRecord::RecordInvalid) { preflight(byte_size: nil) }
    end

    test "an unsuccessful preflight may retain unknown size only with a failure code" do
      ref, = preflight(byte_size: nil, preflight_state: :failed, failure_code: "checksum_size_inconsistent")

      assert_nil ref.byte_size
      assert ref.preflight_failed?
    end

    test "transfer state cannot claim bytes for an unsuccessful preflight" do
      assert_raises(ActiveRecord::RecordInvalid) do
        MediaObjectRef.create!(source_system: "date9ja", source_blob_id: "99", checksum: "c", byte_size: 1,
          content_type: "image/jpeg", source_fingerprint: "f", importer_version: "v1",
          preflight_state: :failed, failure_code: "bad_source", transfer_state: :transferred,
          transferred_at: Time.current)
      end
    end
  end
end
