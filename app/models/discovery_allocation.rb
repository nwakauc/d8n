class DiscoveryAllocation < ApplicationRecord
  belongs_to :brand
  belongs_to :user
  belongs_to :brand_membership
  belongs_to :viewer_profile, class_name: "Profile"

  has_many :allocation_candidates,
    -> { order(:position) },
    class_name: "DiscoveryAllocationCandidate",
    dependent: :restrict_with_exception,
    inverse_of: :discovery_allocation

  scope :kept, -> { where(deleted_at: nil) }

  validates :surface_key, :allocation_date, :time_zone, :strategy_key, :policy_key, :finalized_at, presence: true
  validates :daily_limit, numericality: { only_integer: true, greater_than: 0 }
  validates :surface_key,
    uniqueness: { scope: [ :brand_id, :brand_membership_id, :allocation_date ] }
  validate :records_share_tenant

  private

  def records_share_tenant
    return if brand.blank? || user.blank? || brand_membership.blank? || viewer_profile.blank?
    return if brand_membership.brand_id == brand_id && brand_membership.user_id == user_id &&
      viewer_profile.brand_id == brand_id && viewer_profile.user_id == user_id &&
      viewer_profile.brand_membership_id == brand_membership_id

    errors.add(:base, "records must belong to the same member and brand")
  end
end
