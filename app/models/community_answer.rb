class CommunityAnswer < ApplicationRecord
  include CommunityPublicId
  belongs_to :community_question
  belongs_to :brand
  belongs_to :author_profile, class_name: "Profile"
  belongs_to :reviewed_by_admin_user, class_name: "AdminUser", optional: true
  enum :status, { pending: 0, approved: 1, rejected: 2, hidden: 3 }, prefix: true
  scope :kept, -> { where(deleted_at: nil) }
  scope :published, -> { kept.status_approved.where.not(published_at: nil) }
  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :body, presence: true, length: { maximum: 2_000 }
  validates :moderation_note, length: { maximum: 2_000 }, allow_blank: true
  validate :tenant_ownership

  private

  def tenant_ownership
    errors.add(:author_profile, "must belong to the answer brand") if author_profile && author_profile.brand_id != brand_id
    errors.add(:community_question, "must belong to the answer brand") if community_question && community_question.brand_id != brand_id
  end
end
