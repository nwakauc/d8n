class CommunityStory < ApplicationRecord
  include CommunityPublicId
  belongs_to :brand
  belongs_to :author_profile, class_name: "Profile"
  belongs_to :reviewed_by_admin_user, class_name: "AdminUser", optional: true
  enum :status, { pending: 0, approved: 1, rejected: 2, hidden: 3 }, prefix: true
  # Video remains unavailable until Community has a private Media-owned upload
  # and delivery path (ADR 0033). A string flag without media is not a video.
  CONTENT_TYPES = %w[text].freeze
  scope :kept, -> { where(deleted_at: nil) }
  scope :published, -> { kept.status_approved.where.not(published_at: nil) }
  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :title, presence: true, length: { maximum: 160 }
  validates :body, presence: true, length: { maximum: 3_000 }
  validates :content_type, inclusion: { in: CONTENT_TYPES }
  validates :moderation_note, length: { maximum: 2_000 }, allow_blank: true
  validate :author_matches_brand

  private

  def author_matches_brand
    errors.add(:author_profile, "must belong to the story brand") if author_profile && author_profile.brand_id != brand_id
  end
end
