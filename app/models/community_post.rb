class CommunityPost < ApplicationRecord
  include CommunityPublicId
  belongs_to :community_circle
  belongs_to :brand
  belongs_to :author_profile, class_name: "Profile"
  has_many :community_comments, dependent: :restrict_with_exception
  scope :kept, -> { where(deleted_at: nil) }
  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :body, presence: true, length: { maximum: 4_000 }
  validate :tenant_ownership

  private

  def tenant_ownership
    errors.add(:author_profile, "must belong to the post brand") if author_profile && author_profile.brand_id != brand_id
    errors.add(:community_circle, "must belong to the post brand") if community_circle && community_circle.brand_id != brand_id
  end
end
