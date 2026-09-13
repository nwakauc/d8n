class CommunityCircleMembership < ApplicationRecord
  belongs_to :community_circle
  belongs_to :brand
  belongs_to :profile
  enum :status, { active: 0, left: 1 }, prefix: true
  scope :kept, -> { where(deleted_at: nil) }
  validate :tenant_ownership

  private

  def tenant_ownership
    errors.add(:profile, "must belong to the Circle membership brand") if profile && profile.brand_id != brand_id
    errors.add(:community_circle, "must belong to the Circle membership brand") if community_circle && community_circle.brand_id != brand_id
  end
end
