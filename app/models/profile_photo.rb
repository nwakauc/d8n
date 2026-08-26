class ProfilePhoto < ApplicationRecord
  MAX_FILE_SIZE = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[ image/jpeg image/png image/webp ].freeze

  belongs_to :profile
  belongs_to :user
  belongs_to :brand

  # RAW ORIGINAL: untrusted user upload. Private, owner-only, and never
  # delivered to another user. Purged once the safe derivative is persisted.
  has_one_attached :image
  # SAFE DERIVATIVE: D8N-owned, decoded/re-encoded, metadata-stripped display
  # image. The only representation eligible for delivery to other users.
  has_one_attached :display_image

  enum :status, { pending_review: 0, approved: 1, rejected: 2 }
  enum :visibility, { hidden: 0, visible: 1 }
  # Async safe-derivative pipeline state — orthogonal to status/visibility.
  enum :processing_state, { pending: 0, processing: 1, ready: 2, failed: 3 }, prefix: :processing

  scope :kept, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :id) }
  # Photos eligible for delivery to other eligible users: shown by moderation
  # policy AND with a completed safe derivative. Fails closed on anything else.
  scope :moderation_publicly_eligible, -> { where(status: %i[pending_review approved]) }
  scope :deliverable, -> { kept.visible.processing_ready.moderation_publicly_eligible }

  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :profile_matches_scope
  validate :within_brand_photo_limit, on: :create

  before_validation :ensure_public_id, on: :create
  # The raw-image guarantees are enforced at attach time (:create). They are not
  # re-checked on later lifecycle updates (processing, moderation, soft-delete),
  # because the raw original is intentionally purged once the derivative exists.
  validate :image_is_attached, on: :create
  validate :image_has_allowed_content_type, on: :create
  validate :image_has_allowed_size, on: :create

  # True when a safe derivative exists and this photo may be shown to others.
  def deliverable?
    safe_derivative_ready? && visible? && (pending_review? || approved?)
  end

  def safe_derivative_ready?
    kept? && processing_ready? && display_image.attached?
  end

  def publication_eligible?
    Media::PhotoPolicy.publication_eligible?(photo: self)
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

  def within_brand_photo_limit
    return if profile.blank? || brand.blank?
    return if profile.profile_photos.kept.count < Media::PhotoPolicy.max_count(brand:)

    errors.add(:base, "profile photo limit reached")
  end

  def image_is_attached
    errors.add(:image, "must be attached") unless image.attached?
  end

  def image_has_allowed_content_type
    return unless image.attached?
    return if ALLOWED_CONTENT_TYPES.include?(image.blob.content_type)

    errors.add(:image, "must be a JPEG, PNG, or WebP image")
  end

  def image_has_allowed_size
    return unless image.attached?
    return if image.blob.byte_size <= MAX_FILE_SIZE

    errors.add(:image, "must be smaller than 10MB")
  end
end
