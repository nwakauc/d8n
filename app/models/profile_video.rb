# The brand-profile-owned placement for a member's introduction video (one per
# profile). Storage, processing and delivery reuse the shared D8N Media
# primitives (Media::ObjectKey / VideoContainerValidator / VideoProcessor) —
# this record owns only status, visibility, processing state and soft deletion,
# exactly like ProfilePhoto (ADR 0011 / ADR 0023).
class ProfileVideo < ApplicationRecord
  # MP4 and QuickTime (.mov) only. Both are ISO-BMFF, which Media::Video
  # ContainerValidator structurally validates. WEBM/Matroska is deliberately
  # excluded until the shared validator can walk it — a signature check is not
  # structural validation (ADR 0023).
  ALLOWED_CONTENT_TYPES = %w[ video/mp4 video/quicktime ].freeze

  belongs_to :profile
  belongs_to :user
  belongs_to :brand

  # RAW ORIGINAL: untrusted upload. Private, owner-only, purged once the safe
  # playback rendition exists.
  has_one_attached :video
  # SAFE DERIVATIVES: D8N-generated. The only representations delivered to
  # other users.
  has_one_attached :playback
  has_one_attached :poster

  enum :status, { pending_review: 0, approved: 1, rejected: 2 }
  enum :visibility, { hidden: 0, visible: 1 }
  enum :processing_state, { pending: 0, processing: 1, ready: 2, failed: 3 }, prefix: :processing

  scope :kept, -> { where(deleted_at: nil) }
  scope :moderation_publicly_eligible, -> { where(status: %i[pending_review approved]) }
  scope :deliverable, -> { kept.visible.processing_ready.moderation_publicly_eligible }

  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :duration_seconds,
    numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :profile_matches_scope
  validate :video_is_attached, on: :create

  before_validation :ensure_public_id, on: :create

  # Shown to other eligible users: safe playback ready, visible, not rejected.
  def deliverable?
    safe_derivative_ready? && visible? && (pending_review? || approved?)
  end

  def safe_derivative_ready?
    kept? && processing_ready? && playback.attached?
  end

  def kept?
    deleted_at.nil?
  end

  private

  def ensure_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def profile_matches_scope
    return if profile.blank?
    return if profile.user_id == user_id && profile.brand_id == brand_id

    errors.add(:profile, "must belong to the same user and brand")
  end

  def video_is_attached
    errors.add(:video, "must be attached") unless video.attached?
  end
end
