module Api
  module V1
    module Admin
      class ProfilePhotosController < BaseController
        CODE_STATUS = {
          profile_photo_unavailable: :not_found,
          invalid_photo_moderation_status: :unprocessable_entity,
          profile_photo_moderation_conflict: :conflict
        }.freeze
        QUEUE_LIMIT = 100

        before_action :set_active_storage_url_options, only: :index

        # The moderation review queue: every kept, still-undecided photo for
        # this brand, oldest first. Without this, a moderator has no way to
        # discover which photos are awaiting a decision — the only other
        # entry point into ModerateProfilePhoto is a known photo id (e.g. from
        # a member report). Required for any brand configured moderate-first
        # (see Media::PhotoPolicy) to have a real, usable moderation path.
        def index
          photos = ProfilePhoto.kept.where(brand: Current.brand, status: :pending_review)
            .includes(:profile, display_image_attachment: :blob)
            .order(:created_at, :id).limit(QUEUE_LIMIT)

          render json: { photos: photos.map { |photo| queue_payload(photo) } }
        end

        def update
          result = Trust::ModerateProfilePhoto.call(
            admin_user: Current.admin_user,
            brand: Current.brand,
            photo_id: params[:id],
            decision: params[:status]
          )

          render json: {
            photo: photo_payload(result.photo),
            transitioned: result.transitioned
          }
        rescue Trust::ModerateProfilePhoto::Error => e
          render json: { error: e.code }, status: CODE_STATUS.fetch(e.code)
        end

        private

        def photo_payload(photo)
          {
            id: photo.public_id,
            profile_id: photo.profile.public_id,
            position: photo.position,
            status: photo.status,
            visibility: photo.visibility,
            processing_state: photo.processing_state
          }
        end

        def queue_payload(photo)
          {
            id: photo.public_id,
            profile_id: photo.profile.public_id,
            position: photo.position,
            created_at: photo.created_at.iso8601,
            image: image_payload(photo)
          }
        end

        # Same short-lived, signed, safe-derivative-only delivery a moderator
        # needs to review — never the raw original, never a permanent URL.
        def image_payload(photo)
          return unless photo.display_image.attached?

          blob = photo.display_image.blob
          {
            content_type: blob.content_type,
            url: photo.display_image.url(expires_in: Profiles::PhotoUpload::RETRIEVAL_URL_EXPIRES_IN),
            url_expires_in: Profiles::PhotoUpload::RETRIEVAL_URL_EXPIRES_IN.to_i
          }
        end
      end
    end
  end
end
