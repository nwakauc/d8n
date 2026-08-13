class Conversation < ApplicationRecord
  belongs_to :brand
  belongs_to :match

  has_many :conversation_participants, dependent: :restrict_with_exception
  has_many :profiles, through: :conversation_participants

  enum :status, { active: 0, closed: 1 }, prefix: true

  scope :kept, -> { where(deleted_at: nil) }

  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :match_id, uniqueness: true
  validate :match_belongs_to_brand

  before_validation :ensure_public_id, on: :create

  def other_profile(profile)
    conversation_participants.find { |participant| participant.profile_id != profile.id }&.profile
  end

  private

  def ensure_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def match_belongs_to_brand
    return if match.blank? || match.brand_id == brand_id

    errors.add(:match, "must belong to the same brand")
  end
end
