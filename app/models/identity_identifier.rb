class IdentityIdentifier < ApplicationRecord
  belongs_to :user

  has_many :credentials, dependent: :restrict_with_exception
  has_many :auth_attempts, dependent: :nullify
  has_many :otp_challenges, dependent: :nullify

  enum :kind, { email: 0, phone: 1, oauth_provider_uid: 2, device_fingerprint: 3 }

  scope :kept, -> { where(deleted_at: nil) }

  before_validation :normalize_value

  validates :normalized_value, presence: true, uniqueness: { scope: :kind, conditions: -> { kept } }

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
