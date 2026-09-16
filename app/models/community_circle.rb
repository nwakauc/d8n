class CommunityCircle < ApplicationRecord
  include CommunityPublicId
  belongs_to :brand
  belongs_to :creator_profile, class_name: "Profile"
  belongs_to :reviewed_by_admin_user, class_name: "AdminUser", optional: true
  has_many :community_circle_memberships, dependent: :restrict_with_exception
  has_many :community_posts, dependent: :restrict_with_exception
  enum :status, { pending: 0, approved: 1, rejected: 2, hidden: 3 }, prefix: true
  scope :kept, -> { where(deleted_at: nil) }
  scope :published, -> { kept.status_approved.where.not(published_at: nil) }
  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, presence: true, length: { maximum: 2_000 }
  validates :category, presence: true, length: { maximum: 80 }
  validates :moderation_note, length: { maximum: 2_000 }, allow_blank: true
  validate :creator_matches_brand

  private

  def creator_matches_brand
    errors.add(:creator_profile, "must belong to the Circle brand") if creator_profile && creator_profile.brand_id != brand_id
  end
end
