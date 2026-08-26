class Report < ApplicationRecord
  # Upper bound for reporter-supplied free text (the `note` / API `details`) and
  # the moderator `resolution_note`. Generous for real context, bounded to blunt
  # payload abuse.
  NOTE_MAX_LENGTH = 2_000

  belongs_to :brand
  belongs_to :reporter_profile, class_name: "Profile"
  belongs_to :reported_profile, class_name: "Profile"
  # The admin who last transitioned the report. Nil until a moderator acts.
  belongs_to :reviewed_by, class_name: "AdminUser",
    foreign_key: :reviewed_by_admin_user_id, optional: true

  # Why the reporter flagged the target. Stable internal codes (never renumber —
  # existing rows and analytics depend on them); the frontend maps them to display
  # labels. Codes 0-5 are the original profile-report taxonomy; 6-8 were added for
  # Reporting V2 content safety (see ADR 0018) and are appended, never reordered.
  enum :reason, {
    inappropriate_content: 0,
    harassment: 1,
    spam: 2,
    fake_profile: 3,
    underage: 4,
    other: 5,
    violence_or_threat: 6,
    non_consensual_content: 7,
    impersonation: 8
  }, prefix: :reason

  # What was reported. `profile` (0) is a plain profile report and carries no
  # `target_id`; every other type identifies a specific content record via
  # `target_id` (an internal id) whose owner is mirrored into `reported_profile`.
  # New target types are appended here as the underlying features ship.
  # `conversation` (4) is the whole conversation, for pattern-level harm no
  # single message captures; unlike `message`, its evidence is a bounded window
  # of recent messages rather than a single one (see ADR 0018).
  enum :target_type, {
    profile: 0,
    message: 1,
    profile_media: 2,
    hook: 3,
    conversation: 4
  }, prefix: :target

  # Administrative review lifecycle. `open` until an admin triages it. Only one
  # `open` report may exist per reporter -> target (enforced by partial indexes).
  enum :status, { open: 0, reviewing: 1, actioned: 2, dismissed: 3 }, prefix: :status

  scope :open_reports, -> { where(status: :open) }

  validates :reason, presence: true
  validates :note, length: { maximum: NOTE_MAX_LENGTH }, allow_blank: true
  validates :resolution_note, length: { maximum: NOTE_MAX_LENGTH }, allow_blank: true
  validates :target_id, presence: true, unless: :target_profile?
  validates :target_id, absence: true, if: :target_profile?
  # At most one open report per reporter -> target (DB-enforced too). The scope
  # includes target_type/target_id so distinct content from the same person can
  # each be reported, while a repeat of the same target stays idempotent. Only
  # guards open records so a resolved report never blocks filing a fresh one.
  validates :reporter_profile_id,
    uniqueness: {
      scope: [ :brand_id, :reported_profile_id, :target_type, :target_id ],
      conditions: -> { open_reports }
    },
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
