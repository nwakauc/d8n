# A platform-owned, provider-agnostic geographic catalog entry (country,
# region/province, city/metro, or locality/suburb) used to resolve a member's
# chosen dating location to canonical centroid coordinates. Not brand-owned:
# brands opt in to a set of country codes (BrandContract#place_country_codes)
# rather than owning their own copy of the catalog. Matching never queries
# Place directly — a selection always resolves into the same ProfileLocation
# row/coordinates every other location path uses (Profiles::CurrentPlace).
class Place < ApplicationRecord
  HIERARCHY = %w[ country region city locality ].freeze

  enum :kind, { country: 0, region: 1, city: 2, locality: 3 }
  enum :status, { active: 0, retired: 1 }, prefix: true

  belongs_to :parent, class_name: "Place", optional: true
  has_many :children, class_name: "Place", foreign_key: :parent_id, inverse_of: :parent, dependent: :restrict_with_exception
  has_many :profile_locations, dependent: :restrict_with_exception

  scope :kept, -> { where(deleted_at: nil) }
  scope :selectable, -> { kept.status_active }

  validates :name, presence: true, length: { maximum: 120 }
  validates :code, presence: true, length: { maximum: 60 }, format: { with: /\A[a-z0-9_-]+\z/ }
  validates :country_code, presence: true, length: { is: 2 }
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validate :parent_kind_precedes_own_kind
  validate :country_code_matches_parent

  def self.top_level(country_code:)
    selectable.where(kind: kinds[:region], country_code: country_code.to_s.upcase)
  end

  def self.children_of(place)
    selectable.where(parent_id: place.id)
  end

  # A human-safe, coarse-to-fine label such as "Sea Point, Cape Town" — never
  # includes coordinates. Suitable for the owner profile response.
  def display_path
    [ self, *ancestors ].reject(&:country?).map(&:name).join(", ")
  end

  def ancestors
    Enumerator.new do |yielder|
      current = parent
      while current
        yielder << current
        current = current.parent
      end
    end.to_a
  end

  private

  def parent_kind_precedes_own_kind
    if kind == "country"
      errors.add(:parent, "must be blank for a country") if parent.present?
      return
    end

    if parent.blank?
      errors.add(:parent, "is required")
      return
    end

    expected_parent_kind = HIERARCHY[HIERARCHY.index(kind) - 1]
    return if parent.kind == expected_parent_kind

    errors.add(:parent, "must be a #{expected_parent_kind}")
  end

  def country_code_matches_parent
    return if parent.blank? || country_code.blank?

    errors.add(:country_code, "must match the parent place's country") if parent.country_code != country_code
  end
end
