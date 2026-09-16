# frozen_string_literal: true

require "test_helper"
require "vips"

module Media
  # Concurrency / stale-claim hardening (MEDIA-TRANSFER.md §16b).
  class ProcessProfilePhotoJobClaimTest < ActiveJob::TestCase
    def valid_jpeg
      @valid_jpeg ||= Vips::Image.black(100, 80).add([ 90 ]).cast("uchar").write_to_buffer(".jpg")
    end

    def pending_photo
      brand = Brand.create!(slug: "hookus", name: "HookUs")
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      profile = Profile.create!(brand:, user:, brand_membership: membership,
        display_name: "Ada", birthdate: 25.years.ago.to_date, gender: "woman")
      key = Media::ObjectKey.profile_photo_original(brand:, user:, profile:, content_type: "image/jpeg")
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(valid_jpeg), key:,
        filename: "original.jpg", content_type: "image/jpeg", service_name: ActiveStorage::Blob.service.name)
      photo = ProfilePhoto.new(brand:, user:, profile:)
      photo.image.attach(blob)
      photo.save!
      photo
    end

    test "a stale `processing` claim (crashed worker) is reclaimed and completed" do
      photo = pending_photo
      photo.update_columns(
        processing_state: ProfilePhoto.processing_states[:processing],
        processing_started_at: 30.minutes.ago, processing_claim_token: SecureRandom.uuid
      )

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      photo.reload
      assert photo.processing_ready?
      assert photo.display_image.attached?
      assert_nil photo.processing_claim_token
      assert_nil photo.processing_started_at
    end

    test "a recent `processing` claim is left to its owner" do
      photo = pending_photo
      token = SecureRandom.uuid
      photo.update_columns(
        processing_state: ProfilePhoto.processing_states[:processing],
        processing_started_at: 10.seconds.ago, processing_claim_token: token
      )

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      photo.reload
      assert photo.processing_processing?
      assert_equal token, photo.processing_claim_token
      refute photo.display_image.attached?
    end

    test "a worker that wakes after its claim was reclaimed cannot finalize (ABA)" do
      photo = pending_photo
      stolen_token = SecureRandom.uuid
      real = Media::ImageProcessor.call(valid_jpeg)

      stub_method(Media::ImageProcessor, :call, lambda { |_bytes, **|
        # Another worker reclaims mid-flight.
        ProfilePhoto.where(id: photo.id).update_all(
          processing_state: ProfilePhoto.processing_states[:processing],
          processing_started_at: Time.current, processing_claim_token: stolen_token
        )
        real
      }) do
        perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }
      end

      photo.reload
      assert_equal stolen_token, photo.processing_claim_token, "the losing worker must not touch state"
      refute photo.processing_ready?
      refute photo.display_image.attached?
    end

    test "duplicate executions produce exactly one derivative and one ready state" do
      photo = pending_photo
      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }
      first = photo.reload.display_image.blob.id
      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      assert photo.reload.processing_ready?
      assert_equal first, photo.display_image.blob.id
      assert_equal 1, ActiveStorage::Attachment.where(record: photo, name: "display_image").count
    end

    test "a terminal failure is recorded and not retried into a loop" do
      photo = pending_photo
      photo.image.blob.update_columns(content_type: "image/jpeg")
      photo.image.blob.service.upload(photo.image.blob.key, StringIO.new("garbage-not-an-image"))

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      photo.reload
      assert photo.processing_failed?
      assert_equal "terminal", photo.metadata["processing_failure_kind"]
      assert_nil photo.processing_claim_token
    end

    test "transient failure that exhausts retries is marked terminal (not endlessly sweepable)" do
      photo = pending_photo
      photo.image.blob.update_columns(key: "missing/#{SecureRandom.uuid}/original.jpg") # break raw download

      job = ProcessProfilePhotoJob.new(photo.id)
      job.executions = ProcessProfilePhotoJob::MAX_ATTEMPTS # simulate the final attempt
      assert_raises(ProcessProfilePhotoJob::TransientError) { job.perform(photo.id) }

      photo.reload
      assert photo.processing_failed?
      assert_equal "terminal", photo.metadata["processing_failure_kind"]
      refute ProfilePhoto.processing_sweepable.exists?(id: photo.id)
    end

    test "transient failure with retries remaining stays retryable-sweepable" do
      photo = pending_photo
      photo.image.blob.update_columns(key: "missing/#{SecureRandom.uuid}/original.jpg")

      job = ProcessProfilePhotoJob.new(photo.id)
      job.executions = 1
      assert_raises(ProcessProfilePhotoJob::TransientError) { job.perform(photo.id) }

      photo.reload
      assert photo.processing_failed?
      assert_nil photo.metadata["processing_failure_kind"]
      assert ProfilePhoto.processing_sweepable.exists?(id: photo.id)
    end

    test "a lost-claim worker does not attach a derivative and does not raise" do
      photo = pending_photo
      other = SecureRandom.uuid
      real = Media::ImageProcessor.call(valid_jpeg)
      stub_method(Media::ImageProcessor, :call, lambda { |_b, **|
        ProfilePhoto.where(id: photo.id).update_all(processing_claim_token: other, processing_started_at: Time.current)
        real
      }) do
        assert_nothing_raised { perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) } }
      end
      refute photo.reload.display_image.attached?
    end

    test "ready with a valid derivative is an idempotent no-op" do
      photo = pending_photo
      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }
      photo.reload
      updated = photo.updated_at

      travel 1.second
      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }
      assert_equal updated.to_i, photo.reload.updated_at.to_i
    end

    # --- Review Finding 1: strong display validation on every ready path -------

    def ready_photo
      photo = pending_photo
      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }
      photo.reload
      assert photo.processing_ready?
      refute photo.image.attached?, "raw purged after a real success"
      assert photo.metadata["display_object_key"].present?
      photo
    end

    test "ready + raw purged + exact valid display -> safe no-op" do
      photo = ready_photo
      dblob = photo.display_image.blob.id

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      photo.reload
      assert photo.processing_ready?
      assert_equal dblob, photo.display_image.blob.id
    end

    test "ready + raw purged + wrong exact display key (right suffix) -> not trusted, fails closed" do
      photo = ready_photo
      wrong = photo.metadata["display_object_key"].sub(%r{/[^/]+/display\.jpg\z}, "/#{SecureRandom.uuid}/display.jpg")
      photo.update_columns(metadata: photo.metadata.merge("display_object_key" => wrong))

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      photo.reload
      refute photo.processing_ready?, "a mismatched deterministic key is never a completed transfer"
      assert photo.processing_terminal_failure?
    end

    test "ready + raw purged + wrong storage service -> not trusted" do
      photo = ready_photo
      photo.display_image.blob.update_columns(service_name: "brand_test")

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      refute photo.reload.processing_ready?
      assert photo.processing_terminal_failure?
    end

    test "ready + raw purged + missing remote display object -> not trusted" do
      photo = ready_photo
      photo.display_image.blob.service.delete(photo.display_image.blob.key)

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      refute photo.reload.processing_ready?
      assert photo.processing_terminal_failure?
    end

    test "ready + raw purged + tampered remote bytes -> not trusted" do
      photo = ready_photo
      photo.display_image.blob.service.upload(photo.display_image.blob.key, StringIO.new("not an image at all"))

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      refute photo.reload.processing_ready?
      assert photo.processing_terminal_failure?
    end

    test "ready + raw purged + byte_size mismatch -> not trusted" do
      photo = ready_photo
      photo.display_image.blob.update_columns(byte_size: photo.display_image.blob.byte_size + 5)

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      refute photo.reload.processing_ready?
      assert photo.processing_terminal_failure?
    end

    test "ready + raw purged + checksum mismatch -> not trusted" do
      photo = ready_photo
      photo.display_image.blob.update_columns(checksum: Digest::MD5.base64digest("different"))

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      refute photo.reload.processing_ready?
      assert photo.processing_terminal_failure?
    end

    test "ready + raw purged + non-decodable bytes of the right size -> not trusted" do
      photo = ready_photo
      blob = photo.display_image.blob
      junk = SecureRandom.bytes(blob.byte_size)
      blob.service.upload(blob.key, StringIO.new(junk))
      blob.update_columns(checksum: Digest::MD5.base64digest(junk))

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      refute photo.reload.processing_ready?
      assert photo.processing_terminal_failure?
    end

    test "ready + raw STILL present + no display attached -> repaired to a valid ready state" do
      photo = pending_photo
      photo.update_columns(processing_state: ProfilePhoto.processing_states[:ready])

      perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) }

      photo.reload
      assert photo.processing_ready?
      assert photo.display_image.attached?
      assert_not photo.image.attached?, "raw purged once the real derivative exists"
      assert_equal "image/jpeg", photo.display_image.blob.content_type
    end

    test "an unrecoverable ready photo fails closed once and idempotently" do
      photo = ready_photo
      photo.display_image.blob.service.delete(photo.display_image.blob.key)

      2.times { perform_enqueued_jobs { ProcessProfilePhotoJob.perform_now(photo.id) } }

      photo.reload
      refute photo.processing_ready?, "never silently back to ready"
      assert photo.processing_terminal_failure?
      assert_equal "display_unrecoverable", photo.metadata["processing_failure_reason"]
    end
  end
end
