module Api
  module V1
    module Admin
      class ProfilePhotosController < BaseController
        CODE_STATUS = {
          profile_photo_unavailable: :not_found,
          invalid_photo_moderation_status: :unprocessable_entity,
          profile_photo_moderation_conflict: :conflict
        }.freeze

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
      end
    end
  end
end
