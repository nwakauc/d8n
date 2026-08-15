require "test_helper"

module Profiles
  class PhotoUploadTest < ActiveSupport::TestCase
    test "detects supported image signatures from the leading bytes" do
      assert_equal "image/jpeg", PhotoUpload.detect_image_type("\xFF\xD8\xFF\xE0 rest".b)
      assert_equal "image/png", PhotoUpload.detect_image_type("\x89PNG\r\n\x1A\n rest".b)
      assert_equal "image/webp", PhotoUpload.detect_image_type("RIFF\x00\x00\x00\x00WEBPVP8 ".b)
    end

    test "rejects non-image and truncated signatures" do
      assert_nil PhotoUpload.detect_image_type("plain text")
      assert_nil PhotoUpload.detect_image_type("GIF89a".b)
      assert_nil PhotoUpload.detect_image_type("RIFF".b) # too short for WEBP marker
      assert_nil PhotoUpload.detect_image_type("")
      assert_nil PhotoUpload.detect_image_type(nil)
    end

    test "constants mirror the ProfilePhoto policy" do
      assert_equal ProfilePhoto::MAX_FILE_SIZE, PhotoUpload::MAX_FILE_SIZE
      assert_equal ProfilePhoto::ALLOWED_CONTENT_TYPES, PhotoUpload::ALLOWED_CONTENT_TYPES
    end
  end
end
