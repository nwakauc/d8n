module Profiles
  class PhotoLibrary
    def self.list(user:, brand:)
      profile = Profile.kept.find_by(user:, brand:)
      return ProfilePhoto.none if profile.blank?

      profile.profile_photos.kept.ordered.with_attached_image
    end

    def self.add!(user:, brand:, image:, position: nil)
      profile = Profile.kept.find_by!(user:, brand:)
      photo = ProfilePhoto.new(
        profile:,
        user:,
        brand:,
        position: position.presence || next_position(profile)
      )
      photo.image.attach(image)
      photo.save!
      photo
    end

    def self.soft_delete!(user:, brand:, id:)
      photo = ProfilePhoto.kept.find_by!(id:, user:, brand:)
      photo.update!(deleted_at: Time.current, visibility: :hidden)
      photo.image.purge_later if photo.image.attached?
      photo
    end

    def self.next_position(profile)
      profile.profile_photos.kept.maximum(:position).to_i + 1
    end
  end
end
