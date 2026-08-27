module Media
  # Asynchronously turns a freshly attached, cheaply-sniffed chat attachment
  # into a delivery-ready one. Mirrors Media::ProcessProfilePhotoJob's shape,
  # branching on media_kind:
  #
  #   image: raw original (private, RETAINED) -> decode -> re-encode/strip
  #          metadata TWICE (bandwidth-friendly inline-view rendition, and a
  #          separate higher-fidelity sanitized download rendition — see
  #          Media::ImageProcessor) -> mark ready
  #   video: raw original (private, RETAINED) -> full ISO-BMFF structural walk
  #          (Media::VideoContainerValidator, unchanged safety/codec gate) ->
  #          Media::VideoProcessor (ffprobe-driven transcode-only-if-needed to
  #          H.264/AAC MP4, plus a server-generated poster frame re-encoded
  #          through Media::ImageProcessor) -> mark ready
  #
  # `ready` requires every derivative the media kind needs to actually exist
  # (see MessageAttachment#deliverable?) — never merely that the original
  # passed validation. The raw original is never purged: it is retained
  # internally for reprocessing/report evidence, but (per D8N Chat Media 1.1)
  # is no longer exposed to a recipient as a download for images; video
  # download still serves the original (out of this ticket's privacy scope).
  #
  # Idempotent and tolerant of deletion mid-flight. Transient failures (storage
  # hiccups, an ffmpeg/ffprobe wall-clock timeout under worker load) retry with
  # backoff; once retries are exhausted the attachment is explicitly marked
  # `failed` rather than left stuck in `processing` forever. A genuinely
  # malformed/corrupt/unsupported-codec upload, or a real (non-timeout)
  # transcode/poster failure, is a terminal `failed` state immediately, never
  # retried.
  class ProcessMessageAttachmentJob < ApplicationJob
    queue_as :default

    class TransientError < StandardError; end

    retry_on TransientError, wait: :polynomially_longer, attempts: 5 do |job, error|
      attachment = MessageAttachment.find_by(id: job.arguments.first)
      next if attachment.nil? || attachment.deleted_at.present? || attachment.deliverable?

      attachment.update!(processing_state: :failed)
      Rails.logger.error("[media] message_attachment=#{attachment.id} exhausted retries: #{error.class}")
    end
    discard_on ActiveJob::DeserializationError

    def perform(message_attachment_id)
      attachment = MessageAttachment.find_by(id: message_attachment_id)
      return if attachment.nil? || attachment.deleted_at.present?
      return if attachment.deliverable?
      return unless attachment.original.attached?

      attachment.update!(processing_state: :processing) unless attachment.processing_processing?

      if attachment.image?
        process_image(attachment)
      else
        process_video(attachment)
      end
    end

    private

    def process_image(attachment)
      raw = download(attachment.original)
      display = safely_process_image(
        attachment, raw,
        max_dimension: Media::ImageProcessor::DISPLAY_MAX_DIMENSION, quality: Media::ImageProcessor::JPEG_QUALITY
      )
      return if display.nil? # terminal failure already recorded

      download_quality = safely_process_image(
        attachment, raw,
        max_dimension: Media::ImageProcessor::DOWNLOAD_MAX_DIMENSION, quality: Media::ImageProcessor::DOWNLOAD_JPEG_QUALITY
      )
      return if download_quality.nil? # terminal failure already recorded

      persist_image_renditions(attachment, display, download_quality)
    end

    def process_video(attachment)
      raw = download(attachment.original)
      return if safely_validate_video(attachment, raw).nil? # terminal failure already recorded

      transcode = safely_transcode_video(attachment, raw)
      return if transcode.nil? # terminal failure already recorded, or TransientError already raised

      poster = safely_process_poster(attachment, transcode.poster_bytes)
      return if poster.nil? # terminal failure already recorded

      persist_video_rendition(attachment, transcode, poster)
    end

    def download(attached)
      attached.download
    rescue StandardError => e
      raise TransientError, "raw download failed: #{e.class}"
    end

    def safely_process_image(attachment, raw, max_dimension:, quality:)
      Media::ImageProcessor.call(raw, max_dimension:, quality:)
    rescue Media::ImageProcessor::Error => e
      fail!(attachment, e)
      nil
    end

    def safely_validate_video(attachment, raw)
      Media::VideoContainerValidator.call(raw)
    rescue Media::VideoContainerValidator::Error => e
      fail!(attachment, e)
      nil
    end

    # A wall-clock timeout is treated as TRANSIENT (retried) — a busy worker
    # node, not the file itself, is the likely cause. Every other
    # Media::VideoProcessor failure (unprobeable, undecodable, encoder
    # rejection) is terminal: retrying would not change the outcome.
    def safely_transcode_video(attachment, raw)
      Media::VideoProcessor.call(raw)
    rescue Media::VideoProcessor::TimedOut => e
      raise TransientError, "video processing timed out: #{e.message}"
    rescue Media::VideoProcessor::Error => e
      fail!(attachment, e)
      nil
    end

    def safely_process_poster(attachment, poster_bytes)
      Media::ImageProcessor.call(poster_bytes)
    rescue Media::ImageProcessor::Error => e
      fail!(attachment, e)
      nil
    end

    def fail!(attachment, error)
      attachment.update!(processing_state: :failed)
      Rails.logger.warn("[media] message_attachment=#{attachment.id} processing failed: #{error.class}")
    end

    def persist_image_renditions(attachment, display, download_quality)
      attachment.reload
      return if attachment.deleted_at.present?

      rendition_key = Media::ObjectKey.message_attachment_rendition(attachment.original.blob.key)
      rendition_blob = image_blob(attachment, display, rendition_key, Media::ObjectKey::DISPLAY_BASENAME)
      attachment.rendition.attach(rendition_blob) unless attachment.rendition.attached?

      download_key = Media::ObjectKey.message_attachment_download(attachment.original.blob.key)
      download_blob = image_blob(attachment, download_quality, download_key, Media::ObjectKey::DOWNLOAD_BASENAME)
      attachment.download_rendition.attach(download_blob) unless attachment.download_rendition.attached?

      attachment.update!(processing_state: :ready, width: display.width, height: display.height)
    rescue ActiveRecord::RecordNotFound
      # deleted mid-flight — nothing to persist
    rescue StandardError => e
      raise TransientError, "rendition persist failed: #{e.class}"
    end

    def persist_video_rendition(attachment, transcode, poster)
      attachment.reload
      return if attachment.deleted_at.present?

      if transcode.transcoded
        playback_key = Media::ObjectKey.message_attachment_playback(attachment.original.blob.key)
        playback_blob = video_playback_blob(attachment, transcode, playback_key)
        attachment.rendition.attach(playback_blob) unless attachment.rendition.attached?
      else
        # ffprobe confirmed the original is already H.264/AAC/MP4 — the
        # rendition IS the original, byte-identical, no extra storage.
        attachment.rendition.attach(attachment.original.blob) unless attachment.rendition.attached?
      end

      # The SERVER poster always supersedes any client-supplied one attached
      # at send time (MessageAttachmentUpload#attach_poster!) — it is the
      # production source of truth, never merely a fallback.
      poster_key = Media::ObjectKey.message_attachment_poster(attachment.original.blob.key)
      attachment.poster.attach(video_poster_blob(attachment, poster, poster_key))

      attachment.update!(
        processing_state: :ready,
        width: transcode.width, height: transcode.height, duration_seconds: transcode.duration_seconds
      )
    rescue ActiveRecord::RecordNotFound
      # deleted mid-flight — nothing to persist
    rescue StandardError => e
      raise TransientError, "rendition persist failed: #{e.class}"
    end

    def image_blob(attachment, result, key, filename)
      ActiveStorage::Blob.find_by(key:) || ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(result.bytes), key:, filename:, content_type: result.content_type,
        service_name: attachment.original.blob.service_name
      )
    end

    def video_playback_blob(attachment, transcode, key)
      ActiveStorage::Blob.find_by(key:) || ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(transcode.rendition_bytes), key:, filename: Media::ObjectKey::PLAYBACK_BASENAME,
        content_type: "video/mp4", service_name: attachment.original.blob.service_name
      )
    end

    def video_poster_blob(attachment, poster, key)
      ActiveStorage::Blob.find_by(key:) || ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(poster.bytes), key:, filename: Media::ObjectKey::POSTER_BASENAME,
        content_type: poster.content_type, service_name: attachment.original.blob.service_name
      )
    end
  end
end
