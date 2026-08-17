module Profiles
  class PhotoLibrary
    def self.list(user:, brand:)
      profile = Profile.kept.find_by(user:, brand:)
      return ProfilePhoto.none if profile.blank?

      profile.profile_photos.kept.ordered.with_attached_image.with_attached_display_image
    end

    def self.soft_delete!(user:, brand:, id:)
      profile = Profile.kept.find_by!(user:, brand:)
      photo = nil

      profile.with_lock do
        photo = ProfilePhoto.kept.find_by!(id:, user:, brand:, profile:)
        photo.update!(deleted_at: Time.current, visibility: :hidden)
        Publication.unpublish_if_incomplete!(profile:)
      end

      # Remove both the raw original (if still present) and the safe derivative
      # so a normal delete never leaves an orphaned R2 object.
      photo.image.purge_later if photo.image.attached?
      photo.display_image.purge_later if photo.display_image.attached?
      photo
    end
  end
end
