module Profiles
  # Owns the single ordering invariant for a profile's kept photos. Primary is
  # derived from this order; no independent primary flag exists.
  class PhotoOrder
    InvalidOrder = Class.new(StandardError)

    def self.reorder!(user:, brand:, ids:)
      profile = Profile.kept.find_by!(user:, brand:)
      normalized_ids = normalize_ids(ids)

      profile.with_lock do
        photos = profile.profile_photos.kept.ordered.to_a
        raise InvalidOrder unless normalized_ids.sort == photos.map(&:id).sort

        assign_positions!(photos.index_by(&:id).values_at(*normalized_ids))
      end

      profile.profile_photos.kept.ordered.with_attached_image.with_attached_display_image
    end

    # Makes a collision-free sequential slot for a new photo while the caller
    # holds the profile lock. Existing attach clients may request an insertion
    # point; omitted positions append. Subsequent reorders use `reorder!`.
    def self.prepare_insert!(profile:, position: nil)
      photos = profile.profile_photos.kept.ordered.to_a
      target = position.nil? || position == "" ? photos.length : strict_integer(position)
      raise InvalidOrder unless target.between?(0, photos.length)

      move_temporarily!(photos)
      photos.each_with_index do |photo, index|
        photo.update_columns(position: index >= target ? index + 1 : index, updated_at: Time.current)
      end
      target
    end

    def self.normalize_ids(ids)
      raise InvalidOrder unless ids.is_a?(Array) && ids.all? { |id| id.is_a?(Integer) }
      raise InvalidOrder unless ids.uniq.length == ids.length

      ids
    end
    private_class_method :normalize_ids

    def self.strict_integer(value)
      return value if value.is_a?(Integer)

      raise InvalidOrder
    end
    private_class_method :strict_integer

    def self.assign_positions!(photos)
      move_temporarily!(photos)
      photos.each_with_index do |photo, index|
        photo.update_columns(position: index, updated_at: Time.current)
      end
    end
    private_class_method :assign_positions!

    def self.move_temporarily!(photos)
      offset = photos.filter_map(&:position).max.to_i + photos.length + 1
      photos.each do |photo|
        photo.update_columns(position: photo.position + offset, updated_at: Time.current)
      end
    end
    private_class_method :move_temporarily!
  end
end
