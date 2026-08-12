class ProfilePhoto < ApplicationRecord
  MAX_FILE_SIZE = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[ image/jpeg image/png image/webp ].freeze

  belongs_to :profile
  belongs_to :user
  belongs_to :brand

  has_one_attached :image

  enum :status, { pending_review: 0, approved: 1, rejected: 2 }
  enum :visibility, { hidden: 0, visible: 1 }

  scope :kept, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :profile_matches_scope
  validate :image_is_attached
  validate :image_has_allowed_content_type
  validate :image_has_allowed_size

  private

  def profile_matches_scope
    return if profile.blank?
    return if profile.user_id == user_id && profile.brand_id == brand_id

    errors.add(:profile, "must belong to the same user and brand")
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
