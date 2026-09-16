class CommunityQuestion < ApplicationRecord
  include CommunityPublicId
  belongs_to :brand
  CATEGORIES = %w[dating marriage long_distance family talking_stage red_flags other].freeze
  belongs_to :author_profile, class_name: "Profile"
  belongs_to :selected_answer, class_name: "CommunityAnswer", optional: true
  belongs_to :reviewed_by_admin_user, class_name: "AdminUser", optional: true
  has_many :community_answers, dependent: :restrict_with_exception
  enum :status, { pending: 0, approved: 1, rejected: 2, hidden: 3 }, prefix: true
  enum :selection_status, { selection_pending: 0, selection_selected: 1, selection_no_eligible_answers: 2 }, prefix: true
  scope :kept, -> { where(deleted_at: nil) }
  scope :published, -> { kept.status_approved.where.not(published_at: nil) }
  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :category, inclusion: { in: CATEGORIES }
  validates :body, presence: true, length: { maximum: 2_000 }
  validates :moderation_note, length: { maximum: 2_000 }, allow_blank: true
  validates :closes_at, presence: true
  validate :author_matches_brand
  validate :selected_answer_matches_question

  private

  def author_matches_brand
    errors.add(:author_profile, "must belong to the question brand") if author_profile && author_profile.brand_id != brand_id
  end


  def selected_answer_matches_question
    return if selected_answer.blank? || selected_answer.community_question_id == id

    errors.add(:selected_answer, "must belong to the question")
  end
end
