module Profiles
  class PhotoLibrary
    def self.list(user:, brand:)
      profile = Profile.kept.find_by(user:, brand:)
      return ProfilePhoto.none if profile.blank?

      profile.profile_photos.kept.ordered.with_attached_image
    end

    def self.soft_delete!(user:, brand:, id:)
      profile = Profile.kept.find_by!(user:, brand:)
      photo = nil

      profile.with_lock do
        photo = ProfilePhoto.kept.find_by!(id:, user:, brand:, profile:)
        photo.update!(deleted_at: Time.current, visibility: :hidden)
        Publication.unpublish_if_incomplete!(profile:)
      end

      photo.image.purge_later if photo.image.attached?
      photo
    end
  end
end
