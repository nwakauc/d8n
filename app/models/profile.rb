class Profile < ApplicationRecord
  MINIMUM_AGE = 18
  PUBLIC_ID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  belongs_to :user
  belongs_to :brand
  belongs_to :brand_membership

  has_one :profile_preference, dependent: :restrict_with_exception
  has_many :profile_photos, dependent: :restrict_with_exception
  has_many :profile_option_selections, dependent: :restrict_with_exception
  has_many :selected_profile_options, through: :profile_option_selections, source: :profile_option
  has_many :profile_locations, dependent: :restrict_with_exception
  has_many :likes_given, class_name: "Like", foreign_key: :liker_profile_id, dependent: :restrict_with_exception
  has_many :likes_received, class_name: "Like", foreign_key: :liked_profile_id, dependent: :restrict_with_exception
  has_many :passes_given, class_name: "ProfilePass", foreign_key: :passer_profile_id, dependent: :restrict_with_exception
  has_many :passes_received, class_name: "ProfilePass", foreign_key: :passed_profile_id, dependent: :restrict_with_exception
  has_many :matches_as_profile_a, class_name: "Match", foreign_key: :profile_a_id, dependent: :restrict_with_exception
  has_many :matches_as_profile_b, class_name: "Match", foreign_key: :profile_b_id, dependent: :restrict_with_exception
  has_many :conversation_participants, dependent: :restrict_with_exception
  has_many :conversations, through: :conversation_participants

  enum :status, { draft: 0, active: 1, suspended: 2 }
  enum :visibility, { hidden: 0, visible: 1 }

  scope :kept, -> { where(deleted_at: nil) }

  validates :user_id, uniqueness: { scope: :brand_id, conditions: -> { kept } }
  validates :public_id, presence: true, uniqueness: true, format: { with: PUBLIC_ID_FORMAT }
  validates :display_name, length: { maximum: 80 }, allow_blank: true
  validates :bio, length: { maximum: 1_000 }, allow_blank: true
  validates :gender, length: { maximum: 40 }, allow_blank: true
  validates :country_code, format: { with: /\A[A-Z]{2}\z/ }, allow_blank: true
  validates :city, :occupation, length: { maximum: 120 }, allow_blank: true
  validates :height_cm,
    numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 250 },
    allow_nil: true
  validates :body_type, length: { maximum: 80 }, allow_blank: true
  validates :smoking, :drinking, :fitness,
    inclusion: { in: %w[ never occasionally regularly ] },
    allow_blank: true
  validate :birthdate_meets_minimum_age
  validate :brand_membership_matches_profile_scope
  validate :languages_spoken_are_valid

  before_validation :ensure_public_id, on: :create
  before_validation :normalize_profile_details

  private

  def ensure_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def birthdate_meets_minimum_age
    return if birthdate.blank?
    return if birthdate <= MINIMUM_AGE.years.ago.to_date

    errors.add(:birthdate, "must be at least #{MINIMUM_AGE} years ago")
  end

  def brand_membership_matches_profile_scope
    return if brand_membership.blank?
    return if brand_membership.user_id == user_id && brand_membership.brand_id == brand_id

    errors.add(:brand_membership, "must belong to the same user and brand")
  end

  def languages_spoken_are_valid
    unless languages_spoken.is_a?(Array)
      errors.add(:languages_spoken, "must be an array")
      return
    end

    errors.add(:languages_spoken, "cannot have more than 15 entries") if languages_spoken.size > 15
    errors.add(:languages_spoken, "contains an invalid value") if languages_spoken.any? { |value| !value.is_a?(String) || value.length > 40 }
  end

  def normalize_profile_details
    self.country_code = country_code.to_s.strip.upcase.presence
    self.city = city.to_s.strip.presence
    self.occupation = occupation.to_s.strip.presence
    self.body_type = body_type.to_s.strip.presence
    return unless languages_spoken.is_a?(Array)

    self.languages_spoken = languages_spoken.map do |value|
      value.is_a?(String) ? value.strip.presence : value
    end.compact.uniq
  end
end
