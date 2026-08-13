class ProfileBlock < ApplicationRecord
  belongs_to :brand
  belongs_to :blocker_profile, class_name: "Profile"
  belongs_to :blocked_profile, class_name: "Profile"

  scope :kept, -> { where(deleted_at: nil) }

  validates :blocker_profile_id,
    uniqueness: { scope: [ :brand_id, :blocked_profile_id ], conditions: -> { kept } }
  validate :profiles_match_brand
  validate :cannot_block_self

  private

  def profiles_match_brand
    return if blocker_profile.blank? || blocked_profile.blank?
    return if blocker_profile.brand_id == brand_id && blocked_profile.brand_id == brand_id

    errors.add(:base, "profiles must belong to the same brand")
  end

  def cannot_block_self
    errors.add(:blocked_profile, "cannot be the blocker profile") if blocker_profile_id == blocked_profile_id
  end
end
