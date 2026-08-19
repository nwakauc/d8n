class AddContentTargetsToReports < ActiveRecord::Migration[8.1]
  # Reporting V2: evolve reports from profile-only into content-level reporting
  # (message / profile photo / Hook) on a reusable polymorphic-target seam, while
  # keeping the profile-report contract byte-for-byte compatible.
  #
  # `reported_profile_id` STAYS the responsible person (server-derived from the
  # target — the message sender, photo owner, or Hook sender), so a moderator can
  # always answer "who created this?" without trusting the client. `target_type` +
  # `target_id` identify the specific content (both NULL/`profile` for a plain
  # profile report). `evidence` is an immutable, minimal moderation snapshot so a
  # later-deleted message/Hook/photo can still be understood; it deliberately never
  # holds R2 keys, URLs, or auth data (see ADR 0018).
  def change
    # 0 = profile (existing rows default here, preserving their meaning).
    add_column :reports, :target_type, :integer, null: false, default: 0
    add_column :reports, :target_id, :bigint
    add_column :reports, :evidence, :jsonb, null: false, default: {}

    # Replace the profile-only open-pair guard. Splitting into two partial-unique
    # indexes lets one reporter hold at most one OPEN report per distinct target,
    # so reporting Message A, Message B, and Photo C from the same person all
    # coexist, while a repeat report of the SAME target stays idempotent.
    remove_index :reports, name: "idx_reports_open_pair"

    # Profile reports (no specific content target).
    add_index :reports, [ :brand_id, :reporter_profile_id, :reported_profile_id ],
      unique: true,
      where: "status = 0 AND target_id IS NULL",
      name: "idx_reports_open_profile"

    # Content reports: the (type, id) pair uniquely identifies the target, and the
    # responsible profile is derived from it, so it is not part of the key.
    add_index :reports, [ :brand_id, :target_type, :target_id ],
      unique: true,
      where: "status = 0 AND target_id IS NOT NULL",
      name: "idx_reports_open_target"

    # Moderator queue can filter/scan by target type within a brand.
    add_index :reports, [ :brand_id, :target_type, :created_at ],
      name: "index_reports_on_brand_id_and_target_type_and_created_at"
  end
end
