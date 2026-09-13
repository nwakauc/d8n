class CommunityEvent < ApplicationRecord
  include CommunityPublicId
  belongs_to :brand
  belongs_to :organizer_profile, class_name: "Profile"
  belongs_to :reviewed_by_admin_user, class_name: "AdminUser", optional: true
  has_many :community_event_rsvps, dependent: :restrict_with_exception
  enum :status, { pending: 0, approved: 1, rejected: 2, hidden: 3 }, prefix: true
  scope :kept, -> { where(deleted_at: nil) }
  scope :published, -> { kept.status_approved.where.not(published_at: nil) }
  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :title, presence: true, length: { maximum: 160 }
  validates :description, presence: true, length: { maximum: 2_000 }
  validates :city, presence: true, length: { maximum: 100 }
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :starts_at, presence: true
  validates :moderation_note, length: { maximum: 2_000 }, allow_blank: true
  validate :organizer_matches_brand
  validate :changed_start_is_in_future

  private

  def organizer_matches_brand
    errors.add(:organizer_profile, "must belong to the event brand") if organizer_profile && organizer_profile.brand_id != brand_id
  end

  def changed_start_is_in_future
    return unless will_save_change_to_starts_at? && starts_at.present? && starts_at <= Time.current

    errors.add(:starts_at, "must be in the future")
  end
end
