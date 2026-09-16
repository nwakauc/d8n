class AdminIdentityCorrection < ApplicationRecord
  belongs_to :brand
  belongs_to :profile
  belongs_to :admin_user

  FIELDS = %w[gender interested_in].freeze

  validates :field, inclusion: { in: FIELDS }
  validates :reason, presence: true, length: { maximum: 500 }
  validates :note, length: { maximum: 2_000 }, allow_blank: true
  validate :consistent_brand

  private

  def consistent_brand
    return if profile.blank? || profile.brand_id == brand_id

    errors.add(:profile, "must belong to the same brand")
  end
end
