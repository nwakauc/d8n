class DiscoveryAllocationCandidate < ApplicationRecord
  belongs_to :brand
  belongs_to :discovery_allocation, inverse_of: :allocation_candidates
  belongs_to :candidate_profile, class_name: "Profile"

  scope :kept, -> { where(deleted_at: nil) }

  validates :candidate_profile_id, uniqueness: { scope: :discovery_allocation_id }
  validates :position,
    numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :discovery_allocation_id }
  validates :ranking_payload, presence: true
  validate :records_share_tenant
  validate :candidate_is_not_viewer

  private

  def records_share_tenant
    return if brand.blank? || discovery_allocation.blank? || candidate_profile.blank?
    return if discovery_allocation.brand_id == brand_id && candidate_profile.brand_id == brand_id

    errors.add(:base, "records must belong to the same brand")
  end

  def candidate_is_not_viewer
    return if discovery_allocation.blank?
    return unless candidate_profile_id == discovery_allocation.viewer_profile_id

    errors.add(:candidate_profile, "cannot be the viewer profile")
  end
end
