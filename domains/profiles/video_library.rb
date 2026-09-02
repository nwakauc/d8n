module Profiles
  # Read + lifecycle for the single ProfileVideo on a profile, and the owner /
  # public serialization (ADR 0023). Delivery URLs are short-lived signed
  # capabilities on the D8N-owned derivatives — never the raw original, never a
  # bucket key.
  class VideoLibrary
    class << self
      def find(user:, brand:)
        profile = Profile.kept.find_by(user:, brand:)
        return if profile.nil?

        ProfileVideo.kept.find_by(profile:)
      end

      def soft_delete!(user:, brand:, actor: nil)
        video = find(user:, brand:) || raise(ActiveRecord::RecordNotFound)

        video.update!(
          deleted_at: Time.current,
          deleted_by_id: actor&.id || user&.id,
          deletion_reason: "owner_removed"
        )
        # Product access is gone immediately (kept scope); storage purge runs
        # async and idempotently, like the photo pipeline.
        %i[video playback poster].each do |name|
          attachment = video.public_send(name)
          attachment.purge_later if attachment.attached?
        end
        video
      end

      # Owner sees processing/moderation state and a preview of the safe
      # derivatives (never the raw upload).
      def owner_payload(video)
        return if video.nil?

        {
          id: video.public_id,
          status: video.status,
          visibility: video.visibility,
          processing_state: video.processing_state,
          duration_seconds: video.duration_seconds,
          poster_url: signed_url(video.poster),
          playback_url: signed_url(video.playback)
        }
      end

      # Other users see the video only when it is deliverable under brand
      # moderation policy.
      def public_payload(video)
        return unless video&.deliverable? && Media::VideoPolicy.publication_eligible?(video:)

        {
          id: video.public_id,
          duration_seconds: video.duration_seconds,
          poster_url: signed_url(video.poster),
          playback_url: signed_url(video.playback)
        }
      end

      private

      def signed_url(attachment)
        return nil unless attachment.attached?

        attachment.url(expires_in: VideoUpload::RETRIEVAL_URL_EXPIRES_IN)
      end
    end
  end
end
