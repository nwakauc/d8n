class AiConversation < ApplicationRecord
  ASSISTANT_KEYS = %w[dating_assistant].freeze
  LANGUAGES = %w[english pidgin igbo yoruba hausa french].freeze

  belongs_to :brand
  belongs_to :brand_membership
  has_many :ai_messages, -> { order(:created_at, :id) }, dependent: :restrict_with_exception
  has_many :ai_usage_events, dependent: :restrict_with_exception

  enum :status, { active: 0, archived: 1 }, prefix: true
  enum :safety_status, { none: 0, attention: 1 }, prefix: true

  scope :kept, -> { where(deleted_at: nil) }
  scope :recent_first, -> { order(last_message_at: :desc, created_at: :desc, id: :desc) }

  validates :assistant_key, inclusion: { in: ASSISTANT_KEYS }
  validates :language, inclusion: { in: LANGUAGES }
  validate :membership_belongs_to_brand

  private

  def membership_belongs_to_brand
    return if brand_membership.blank? || brand_membership.brand_id == brand_id

    errors.add(:brand_membership, "must belong to the same brand")
  end
end
