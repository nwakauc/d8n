class FindProfileExposure < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :brand_membership
  belongs_to :viewer_profile, class_name: "Profile"
  belongs_to :candidate_profile, class_name: "Profile"

  validates :candidate_profile_id,
    uniqueness: { scope: [ :brand_id, :brand_membership_id, :exposure_date ] }
  validates :exposure_date, presence: true
  validate :records_share_tenant
  validate :candidate_is_not_viewer

  private

  def records_share_tenant
    return if brand.blank? || user.blank? || brand_membership.blank? || viewer_profile.blank? || candidate_profile.blank?
    return if brand_membership.brand_id == brand_id && brand_membership.user_id == user_id &&
      viewer_profile.brand_id == brand_id && viewer_profile.user_id == user_id &&
      candidate_profile.brand_id == brand_id

    errors.add(:base, "records must belong to the same member and brand")
  end

  def candidate_is_not_viewer
    errors.add(:candidate_profile, "cannot be the viewer profile") if candidate_profile_id == viewer_profile_id
  end
end
