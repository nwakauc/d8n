require "test_helper"

module Media
  class ProcessMessageAttachmentJobTest < ActiveJob::TestCase
    include ActiveJob::TestHelper

    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      BrandDomain.create!(brand: @brand, host: "hookus.test")
      @ada = create_profile(brand: @brand, display_name: "Ada")
      @sam = create_profile(brand: @brand, display_name: "Sam")
      @conversation = conversation_between(@ada, @sam)
      @message = Message.create!(brand: @brand, conversation: @conversation, sender_profile: @ada, body: "media")
    end

    teardown do
      clear_enqueued_jobs
      ActiveStorage::Blob.all.each { |blob| blob.purge rescue nil }
    end

    test "processes an image into inline-view AND sanitized download renditions, records dimensions" do
      attachment = build_attachment(:image, build_test_jpeg_bytes(width: 200, height: 100))

      ProcessMessageAttachmentJob.perform_now(attachment.id)

      attachment.reload
      assert attachment.processing_ready?
      assert attachment.rendition.attached?
      assert attachment.download_rendition.attached?
      assert_not_equal attachment.rendition.blob.id, attachment.download_rendition.blob.id
      assert attachment.original.attached?, "original is retained internally, never exposed to the recipient"
      assert_equal 200, attachment.width
      assert_equal 100, attachment.height
    end

    test "an H.264/AAC/MP4 video needs no transcode: rendition reuses the original blob" do
      attachment = build_attachment(:video, build_test_h264_mp4_bytes)

      ProcessMessageAttachmentJob.perform_now(attachment.id)

      attachment.reload
      assert attachment.processing_ready?
      assert_equal attachment.original.blob.id, attachment.rendition.blob.id, "no unnecessary transcode"
      assert attachment.poster.attached?, "poster is server-generated during processing"
      assert_in_delta 1.0, attachment.duration_seconds.to_f, 0.2
      assert_equal 64, attachment.width
    end

    test "an HEVC video is transcoded to a distinct H.264/AAC rendition" do
      attachment = build_attachment(:video, build_test_hevc_mp4_bytes)

      ProcessMessageAttachmentJob.perform_now(attachment.id)

      attachment.reload
      assert attachment.processing_ready?
      assert_not_equal attachment.original.blob.id, attachment.rendition.blob.id
      assert_equal "video/mp4", attachment.rendition.blob.content_type
      assert attachment.poster.attached?
    end

    test "an H.264/AAC .mov is re-muxed into an MP4 rendition (no browser MOV playback assumed)" do
      attachment = build_attachment(:video, build_test_h264_mov_bytes)

      ProcessMessageAttachmentJob.perform_now(attachment.id)

      attachment.reload
      assert attachment.processing_ready?
      assert_not_equal attachment.original.blob.id, attachment.rendition.blob.id, "container itself needed to change"
      assert_equal "video/mp4", attachment.rendition.blob.content_type
    end

    test "the server poster supersedes a client-supplied poster attached at send time" do
      attachment = build_attachment(:video, build_test_h264_mp4_bytes)
      attachment.poster.attach(io: StringIO.new(build_test_jpeg_bytes(width: 10, height: 10)),
        filename: "client-poster.jpg", content_type: "image/jpeg")
      client_poster_blob_id = attachment.poster.blob.id

      ProcessMessageAttachmentJob.perform_now(attachment.id)

      attachment.reload
      assert attachment.poster.attached?
      assert_not_equal client_poster_blob_id, attachment.poster.blob.id, "server-generated poster must replace the client one"
    end

    test "a corrupt image is a terminal failure, not retried" do
      attachment = build_attachment(:image, "not a real image".b)

      ProcessMessageAttachmentJob.perform_now(attachment.id)

      assert attachment.reload.processing_failed?
      assert_not attachment.rendition.attached?
    end

    test "a corrupt video fails the structural container check before ever reaching ffmpeg" do
      attachment = build_attachment(:video, build_test_mp4_bytes[0, 20])

      ProcessMessageAttachmentJob.perform_now(attachment.id)

      assert attachment.reload.processing_failed?
      assert_not attachment.rendition.attached?
    end

    test "a real but undecodable-by-ffmpeg video (structurally valid, no usable frames) is a terminal failure" do
      attachment = build_attachment(:video, build_test_mp4_bytes(codec: "avc1"))

      ProcessMessageAttachmentJob.perform_now(attachment.id)

      assert attachment.reload.processing_failed?
      assert_not attachment.rendition.attached?
      assert_not attachment.poster.attached?
    end

    test "a real (non-timeout) transcode failure is terminal, not retried" do
      attachment = build_attachment(:video, build_test_h264_mp4_bytes)

      stub_method(Media::VideoProcessor, :call, ->(_bytes) { raise Media::VideoProcessor::TranscodeFailed, "boom" }) do
        ProcessMessageAttachmentJob.perform_now(attachment.id)
      end

      assert attachment.reload.processing_failed?
    end

    test "a wall-clock timeout is transient and, once retries are exhausted, the attachment is marked failed" do
      attachment = build_attachment(:video, build_test_h264_mp4_bytes)

      stub_method(Media::VideoProcessor, :call, ->(_bytes) { raise Media::VideoProcessor::TimedOut, "too slow" }) do
        perform_enqueued_jobs do
          ProcessMessageAttachmentJob.perform_later(attachment.id)
        end
        # Drain every retry the queue schedules until none remain (bounded so a
        # regression that stops retrying — or never stops — fails loudly
        # rather than hanging).
        20.times do
          break if enqueued_jobs.empty?

          perform_enqueued_jobs
        end
      end

      assert_empty enqueued_jobs, "retries must eventually stop, not loop forever"
      assert attachment.reload.processing_failed?, "exhausted retries must leave the attachment failed, never stuck in processing"
    end

    test "is idempotent: re-running a ready attachment is a no-op" do
      attachment = build_attachment(:image, build_test_jpeg_bytes)
      ProcessMessageAttachmentJob.perform_now(attachment.id)
      rendition_blob_id = attachment.reload.rendition.blob.id

      ProcessMessageAttachmentJob.perform_now(attachment.id)

      assert_equal rendition_blob_id, attachment.reload.rendition.blob.id
    end

    test "a deleted-mid-flight attachment is skipped, not resurrected" do
      attachment = build_attachment(:image, build_test_jpeg_bytes)
      attachment.update!(deleted_at: Time.current)

      ProcessMessageAttachmentJob.perform_now(attachment.id)

      assert_not attachment.reload.rendition.attached?
    end

    test "a since-deleted attachment id is a silent no-op" do
      assert_nothing_raised { ProcessMessageAttachmentJob.perform_now(-1) }
    end

    private

    # Attaches with an explicit `.../original.<ext>` key, matching the real
    # key shape Media::ObjectKey allocates in production (Messaging::
    # MessageAttachmentUpload). A flat auto-generated ActiveStorage key (no
    # "original.<ext>" suffix) would make Media::ObjectKey.derived_key's
    # basename-replace logic fall through to its append fallback instead,
    # which is not what real attachments ever look like.
    def build_attachment(kind, bytes)
      attachment = MessageAttachment.new(
        brand: @brand, message: @message, media_kind: kind, position: 0, processing_state: :pending
      )
      ext = kind == :video ? "mp4" : "jpg"
      content_type = kind == :video ? "video/mp4" : "image/jpeg"
      key = "brands/#{@brand.slug}/attachments/#{SecureRandom.uuid}/original.#{ext}"
      attachment.original.attach(io: StringIO.new(bytes), filename: "original.#{ext}", content_type:, key:)
      attachment.save!
      attachment
    end

    def conversation_between(first, second)
      profile_a_id, profile_b_id = Match.canonical_pair(first.id, second.id)
      match = Match.create!(brand: first.brand, profile_a_id:, profile_b_id:)
      Messaging::StartConversation.call(user: first.user, brand: first.brand, match_public_id: match.public_id).conversation
    end

    def create_profile(brand:, display_name: nil)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(
        brand:, user:, brand_membership: membership, display_name:,
        birthdate: 30.years.ago.to_date, gender: "person", status: :active, visibility: :visible
      )
      ProfilePreference.create!(brand:, user:, profile:, min_age: 18, max_age: 80, interested_in: [ "person" ])
      profile
    end
  end
end
