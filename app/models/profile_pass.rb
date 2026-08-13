class ProfilePass < ApplicationRecord
  belongs_to :brand
  belongs_to :passer_profile, class_name: "Profile"
  belongs_to :passed_profile, class_name: "Profile"

  scope :kept, -> { where(deleted_at: nil) }

  validates :passer_profile_id,
    uniqueness: { scope: [ :brand_id, :passed_profile_id ], conditions: -> { kept } }
  validate :profiles_match_brand
  validate :cannot_pass_self

  private

  def profiles_match_brand
    return if passer_profile.blank? || passed_profile.blank?
    return if passer_profile.brand_id == brand_id && passed_profile.brand_id == brand_id

    errors.add(:base, "profiles must belong to the same brand")
  end

  def cannot_pass_self
    errors.add(:passed_profile, "cannot be the passer profile") if passer_profile_id == passed_profile_id
  end
end
