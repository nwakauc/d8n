class Profile < ApplicationRecord
  MINIMUM_AGE = 18
  PUBLIC_ID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  belongs_to :user
  belongs_to :brand
  belongs_to :brand_membership

  has_one :profile_preference, dependent: :restrict_with_exception
  # The single live introduction video (ADR 0023). Scoped to kept rows so it
  # mirrors the one-per-profile partial unique index; soft-deleted videos are
  # invisible here and handled by Profiles::VideoLibrary.
  has_one :profile_video, -> { where(deleted_at: nil) }, dependent: :restrict_with_exception
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

  # Canonical scalar constraints — the VALUES live in Profiles::FieldCatalog
  # (one authoritative place to change a semantic limit); the rules stay
  # explicit here so "why was this profile rejected?" is answerable from the
  # model. Domain invariants below (age gate, tenant scope, languages) stay
  # entirely hand-written.
  catalog = Profiles::FieldCatalog
  validates :display_name, length: { maximum: catalog.max_length("display_name") }, allow_blank: true
  validates :bio, length: { maximum: catalog.max_length("bio") }, allow_blank: true
  validates :gender, length: { maximum: catalog.max_length("gender") }, allow_blank: true
  validates :pronouns, length: { maximum: catalog.max_length("pronouns") }, allow_blank: true
  validates :city, length: { maximum: catalog.max_length("city") }, allow_blank: true
  validates :occupation, length: { maximum: catalog.max_length("occupation") }, allow_blank: true
  validates :job_title, length: { maximum: catalog.max_length("job_title") }, allow_blank: true
  validates :company_name, length: { maximum: catalog.max_length("company_name") }, allow_blank: true
  validates :school_or_institution, length: { maximum: catalog.max_length("school_or_institution") }, allow_blank: true
  validates :looking_for_text, length: { maximum: catalog.max_length("looking_for_text") }, allow_blank: true
  validates :body_type, length: { maximum: catalog.max_length("body_type") }, allow_blank: true
  validates :country_code, format: { with: catalog.format_pattern("country_code") }, allow_blank: true
  validates :height_cm, numericality: catalog.numericality("height_cm"), allow_nil: true
  validates :children_count, numericality: catalog.numericality("children_count"), allow_nil: true
  validates :smoking, :drinking, :fitness,
    inclusion: { in: catalog.allowed_values("smoking") },
    allow_blank: true

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

    limits = Profiles::FieldCatalog.list_limits("languages_spoken")
    if languages_spoken.size > limits.fetch(:max_entries)
      errors.add(:languages_spoken, "cannot have more than #{limits.fetch(:max_entries)} entries")
    end
    if languages_spoken.any? { |value| !value.is_a?(String) || value.length > limits.fetch(:item_max_length) }
      errors.add(:languages_spoken, "contains an invalid value")
    end
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
