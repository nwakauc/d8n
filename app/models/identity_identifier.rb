class IdentityIdentifier < ApplicationRecord
  belongs_to :user
  belongs_to :brand

  has_many :credentials, dependent: :restrict_with_exception
  has_many :auth_attempts, dependent: :nullify
  has_many :otp_challenges, dependent: :nullify

  enum :kind, { email: 0, phone: 1, oauth_provider_uid: 2, device_fingerprint: 3 }

  scope :kept, -> { where(deleted_at: nil) }
  scope :contact, -> { where(kind: %i[email phone]) }

  before_validation :normalize_value

  # Identity is brand-scoped: the same email/phone may independently belong
  # to a different User on a different brand. Each brand registration gets
  # its own User -- there is no cross-brand identity linkage by design.
  validates :normalized_value, presence: true, uniqueness: { scope: [ :kind, :brand_id ], conditions: -> { kept } }

  private

  def normalize_value
    self.normalized_value =
      if phone?
        Identity::PhoneNormalizer.call(normalized_value)
      else
        normalized_value.to_s.strip.downcase
      end
  end
end
