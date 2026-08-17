class Report < ApplicationRecord
  belongs_to :brand
  belongs_to :reporter_profile, class_name: "Profile"
  belongs_to :reported_profile, class_name: "Profile"
  # The admin who last transitioned the report. Nil until a moderator acts.
  belongs_to :reviewed_by, class_name: "AdminUser",
    foreign_key: :reviewed_by_admin_user_id, optional: true

  # Why the reporter flagged the target. Kept small and extensible; the frontend
  # maps these to human-readable labels.
  enum :reason, {
    inappropriate_content: 0,
    harassment: 1,
    spam: 2,
    fake_profile: 3,
    underage: 4,
    other: 5
  }, prefix: :reason

  # Administrative review lifecycle. `open` until an admin triages it. Only one
  # `open` report may exist per reporter -> target pair (enforced by index).
  enum :status, { open: 0, reviewing: 1, actioned: 2, dismissed: 3 }, prefix: :status

  scope :open_reports, -> { where(status: :open) }

  validates :reason, presence: true
  validates :note, length: { maximum: 2_000 }, allow_blank: true
  validates :resolution_note, length: { maximum: 2_000 }, allow_blank: true
  # At most one open report per reporter -> target (DB-enforced too). Only guards
  # open records so a resolved report never blocks filing a fresh one.
  validates :reporter_profile_id,
    uniqueness: { scope: [ :brand_id, :reported_profile_id ], conditions: -> { open_reports } },
    if: :status_open?
  validate :profiles_match_brand
  validate :cannot_report_self

  private

  def profiles_match_brand
    return if reporter_profile.blank? || reported_profile.blank?
    return if reporter_profile.brand_id == brand_id && reported_profile.brand_id == brand_id

    errors.add(:base, "profiles must belong to the same brand")
  end

  def cannot_report_self
    errors.add(:reported_profile, "cannot be the reporter profile") if reporter_profile_id == reported_profile_id
  end
end
