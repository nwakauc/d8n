module Media
  # Asynchronously turns a freshly attached raw profile-photo upload into the
  # safe display derivative that other eligible users may see.
  #
  #   raw original (private) -> decode -> re-encode -> strip metadata ->
  #   store display derivative (private) -> mark ready -> purge raw original
  #
  # Idempotent and tolerant of deletion mid-flight. Transient storage failures
  # retry with backoff; a malformed/oversized image is a terminal `failed`
  # state, never retried forever.
  class ProcessProfilePhotoJob < ApplicationJob
    queue_as :default

    class TransientError < StandardError; end

    retry_on TransientError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    def perform(profile_photo_id)
      photo = ProfilePhoto.find_by(id: profile_photo_id)
      return if photo.nil? || photo.deleted_at.present?                    # deleted before/while queued
      return if photo.processing_ready? && photo.display_image.attached?   # already done (idempotent)
      return unless photo.image.attached?                                  # raw already gone; nothing to do

      photo.update!(processing_state: :processing) unless photo.processing_processing?

      raw = download_raw(photo)
      result = safely_process(photo, raw)
      return if result.nil? # terminal failure already recorded

      persist_derivative(photo, result)
    end

    private

    def download_raw(photo)
      photo.image.download
    rescue StandardError => e
      raise TransientError, "raw download failed: #{e.class}"
    end

    def safely_process(photo, raw)
      Media::ImageProcessor.call(raw)
    rescue Media::ImageProcessor::Error => e
      photo.update!(processing_state: :failed)
      Rails.logger.warn("[media] profile_photo=#{photo.id} processing failed: #{e.class}")
      nil
    end

    def persist_derivative(photo, result)
      # A delete may have landed while we were decoding; re-check before writing.
      photo.reload
      return if photo.deleted_at.present?

      blob = derivative_blob(photo, result)
      photo.display_image.attach(blob) unless photo.display_image.attached?
      photo.update!(processing_state: :ready, processed_at: Time.current)

      # The raw original is sensitive (EXIF/GPS) and no longer needed once the
      # safe derivative exists. Purge it durably.
      photo.image.purge_later if photo.image.attached?
    rescue ActiveRecord::RecordNotFound
      # deleted mid-flight — nothing to persist
    rescue StandardError => e
      raise TransientError, "derivative persist failed: #{e.class}"
    end

    # The display key is derived deterministically from the original's key, so a
    # retry that already uploaded the object reuses the existing blob instead of
    # colliding on the unique key.
    def derivative_blob(photo, result)
      key = Media::ObjectKey.profile_photo_display(photo.image.blob.key)
      ActiveStorage::Blob.find_by(key:) || ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(result.bytes),
        key:,
        filename: Media::ObjectKey::DISPLAY_BASENAME,
        content_type: result.content_type,
        # Persist the derivative beside its source even if the process default
        # changes or this is a legacy HookUs blob on the old `r2` service.
        service_name: photo.image.blob.service_name
      )
    end
  end
end
