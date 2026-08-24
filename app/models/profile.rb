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
  has_many :prompt_answers, class_name: "ProfilePromptAnswer", dependent: :restrict_with_exception
  has_many :profile_locations, dependent: :restrict_with_exception
  has_many :find_exposures_as_viewer,
    class_name: "FindProfileExposure",
    foreign_key: :viewer_profile_id,
    dependent: :restrict_with_exception
  has_many :find_exposures_as_candidate,
    class_name: "FindProfileExposure",
    foreign_key: :candidate_profile_id,
    dependent: :restrict_with_exception
  has_many :discovery_allocations_as_viewer,
    class_name: "DiscoveryAllocation",
    foreign_key: :viewer_profile_id,
    dependent: :restrict_with_exception
  has_many :discovery_allocation_memberships,
    class_name: "DiscoveryAllocationCandidate",
    foreign_key: :candidate_profile_id,
    dependent: :restrict_with_exception
  has_many :likes_given, class_name: "Like", foreign_key: :liker_profile_id, dependent: :restrict_with_exception
  has_many :likes_received, class_name: "Like", foreign_key: :liked_profile_id, dependent: :restrict_with_exception
  has_many :passes_given, class_name: "ProfilePass", foreign_key: :passer_profile_id, dependent: :restrict_with_exception
  has_many :passes_received, class_name: "ProfilePass", foreign_key: :passed_profile_id, dependent: :restrict_with_exception
  has_many :matches_as_profile_a, class_name: "Match", foreign_key: :profile_a_id, dependent: :restrict_with_exception
  has_many :matches_as_profile_b, class_name: "Match", foreign_key: :profile_b_id, dependent: :restrict_with_exception
  has_many :conversation_participants, dependent: :restrict_with_exception
  has_many :conversations, through: :conversation_participants
  has_many :blocks_initiated,
    class_name: "ProfileBlock",
    foreign_key: :blocker_profile_id,
    dependent: :restrict_with_exception
  has_many :blocks_received,
    class_name: "ProfileBlock",
    foreign_key: :blocked_profile_id,
    dependent: :restrict_with_exception

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
  validates :pronouns, length: { maximum: 40 }, allow_blank: true
  validates :job_title, :company_name, length: { maximum: 120 }, allow_blank: true
  validates :school_or_institution, length: { maximum: 160 }, allow_blank: true
  validates :looking_for_text, length: { maximum: 600 }, allow_blank: true
  validates :children_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 30 },
    allow_nil: true
  validate :birthdate_meets_minimum_age
  validate :brand_membership_matches_profile_scope
  validate :languages_spoken_are_valid
  validate :languages_are_valid

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

  # Structured languages (canonical going forward — `languages_spoken` is the
  # retained legacy free-text array, see Profiles::Languages / ADR 0017). The
  # taxonomy + rules live in Profiles::Languages so nothing is hardcoded here.
  def languages_are_valid
    Profiles::Languages.normalize(languages).errors.each do |message|
      errors.add(:languages, message)
    end
  end

  def normalize_profile_details
    self.country_code = country_code.to_s.strip.upcase.presence
    self.city = city.to_s.strip.presence
    self.occupation = occupation.to_s.strip.presence
    self.body_type = body_type.to_s.strip.presence
    self.pronouns = pronouns.to_s.strip.presence
    self.job_title = job_title.to_s.strip.presence
    self.company_name = company_name.to_s.strip.presence
    self.school_or_institution = school_or_institution.to_s.strip.presence
    self.looking_for_text = looking_for_text.to_s.strip.presence
    normalize_languages
    return unless languages_spoken.is_a?(Array)

    self.languages_spoken = languages_spoken.map do |value|
      value.is_a?(String) ? value.strip.presence : value
    end.compact.uniq
  end

  # Only rewrite to canonical form when the input is structurally valid; leaving
  # invalid input untouched lets `languages_are_valid` surface a precise error
  # instead of silently discarding it.
  def normalize_languages
    return unless languages.is_a?(Array)

    result = Profiles::Languages.normalize(languages)
    self.languages = result.entries if result.errors.empty?
  end
end
