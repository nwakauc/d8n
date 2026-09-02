module Media
  # Turns a freshly attached raw profile-video upload into the safe playback
  # rendition + poster frame that other eligible users may see (ADR 0023).
  #
  #   raw original (private) -> full ISO-BMFF structural validation -> brand
  #   duration limit -> ffprobe -> H.264/AAC MP4 rendition (+ stream-copy or
  #   no-op when already compatible) -> poster frame -> store derivatives
  #   (private) -> mark ready -> purge raw original
  #
  # The structural walk (Media::VideoContainerValidator) and duration check run
  # HERE, against the whole downloaded object — a bounded head cannot contain a
  # non-faststart MP4's trailing `moov` box, so validating at attach time would
  # reject legitimate uploads. A structurally invalid file or one over the
  # brand's duration limit is a terminal `failed` state.
  #
  # Same lifecycle contract as Media::ProcessProfilePhotoJob: idempotent,
  # deletion-tolerant, transient-retry with backoff, terminal `failed` for a
  # genuinely unusable file.
  class ProcessProfileVideoJob < ApplicationJob
    queue_as :default

    class TransientError < StandardError; end

    retry_on TransientError, wait: :polynomially_longer, attempts: 5 do |job, _error|
      video = ProfileVideo.find_by(id: job.arguments.first)
      video&.update!(processing_state: :failed) unless video&.processing_ready?
    end
    discard_on ActiveJob::DeserializationError

    def perform(profile_video_id)
      video = ProfileVideo.find_by(id: profile_video_id)
      return if video.nil? || video.deleted_at.present?
      return if video.processing_ready? && video.playback.attached?
      return unless video.video.attached?

      video.update!(processing_state: :processing) unless video.processing_processing?

      raw = download_raw(video)
      container = validate_container(video, raw)
      return if container.nil? # terminal failure recorded
      return if over_duration?(video, container.duration_seconds, source: "container")

      result = safely_process(video, raw)
      return if result.nil?
      return if over_duration?(video, result.duration_seconds, source: "probe")

      persist_derivatives(video, result)
    end

    private

    def download_raw(video)
      video.video.download
    rescue StandardError => e
      raise TransientError, "raw download failed: #{e.class}"
    end

    # Full box-tree walk + codec gate on the whole object. Returns the
    # Validator::Result (which carries a best-effort duration), or nil after
    # recording a terminal failure.
    def validate_container(video, raw)
      Media::VideoContainerValidator.call(raw)
    rescue Media::VideoContainerValidator::Error => e
      terminal_failure(video, "invalid container: #{e.class}")
      nil
    end

    def over_duration?(video, duration_seconds, source:)
      return false if duration_seconds.nil?

      limit = Media::VideoPolicy.max_duration_seconds(brand: video.brand)
      return false if duration_seconds <= limit

      terminal_failure(video, "#{source} duration #{duration_seconds}s exceeds brand limit #{limit}s")
      true
    end

    def terminal_failure(video, reason)
      video.update!(processing_state: :failed)
      Rails.logger.warn("[media] profile_video=#{video.id} rejected: #{reason}")
    end

    def safely_process(video, raw)
      Media::VideoProcessor.call(raw)
    rescue Media::VideoProcessor::TimedOut
      raise TransientError, "video processing timed out"
    rescue Media::VideoProcessor::Error => e
      video.update!(processing_state: :failed)
      Rails.logger.warn("[media] profile_video=#{video.id} processing failed: #{e.class}")
      nil
    end

    def persist_derivatives(video, result)
      video.reload
      return if video.deleted_at.present?

      original_key = video.video.blob.key
      attach_derivative(video, :playback, Media::ObjectKey.profile_video_playback(original_key),
        result.rendition_bytes, "video/mp4", ObjectKey::PLAYBACK_BASENAME)
      if result.poster_bytes
        attach_derivative(video, :poster, Media::ObjectKey.profile_video_poster(original_key),
          result.poster_bytes, "image/jpeg", ObjectKey::POSTER_BASENAME)
      end

      updates = { processing_state: :ready, processed_at: Time.current }
      updates[:duration_seconds] = result.duration_seconds.floor if result.duration_seconds
      video.update!(updates)

      video.video.purge_later if video.video.attached?
    rescue ActiveRecord::RecordNotFound
      # deleted mid-flight
    rescue StandardError => e
      raise TransientError, "derivative persist failed: #{e.class}"
    end

    def attach_derivative(video, name, key, bytes, content_type, basename)
      attachment = video.public_send(name)
      return if attachment.attached?

      blob = ActiveStorage::Blob.find_by(key:) || ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(bytes), key:, filename: basename, content_type:,
        service_name: video.video.blob.service_name
      )
      attachment.attach(blob)
    end
  end
end
