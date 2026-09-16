class CommunityComment < ApplicationRecord
  include CommunityPublicId
  belongs_to :community_post
  belongs_to :brand
  belongs_to :author_profile, class_name: "Profile"
  scope :kept, -> { where(deleted_at: nil) }
  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :body, presence: true, length: { maximum: 2_000 }
  validate :tenant_ownership

  private

  def tenant_ownership
    errors.add(:author_profile, "must belong to the comment brand") if author_profile && author_profile.brand_id != brand_id
    errors.add(:community_post, "must belong to the comment brand") if community_post && community_post.brand_id != brand_id
  end
end
