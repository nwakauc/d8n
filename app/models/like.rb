class Like < ApplicationRecord
  belongs_to :brand
  belongs_to :liker_profile, class_name: "Profile"
  belongs_to :liked_profile, class_name: "Profile"

  enum :kind, { like: 0, hook: 1 }, prefix: true

  scope :kept, -> { where(deleted_at: nil) }

  validates :liker_profile_id,
    uniqueness: { scope: [ :brand_id, :liked_profile_id ], conditions: -> { kept } }
  validate :profiles_match_brand
  validate :cannot_like_self

  private

  def profiles_match_brand
    return if liker_profile.blank? || liked_profile.blank?
    return if liker_profile.brand_id == brand_id && liked_profile.brand_id == brand_id

    errors.add(:base, "profiles must belong to the same brand")
  end

  def cannot_like_self
    errors.add(:liked_profile, "cannot be the liker profile") if liker_profile_id == liked_profile_id
  end
end
