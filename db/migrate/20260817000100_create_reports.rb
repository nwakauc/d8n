class CreateReports < ActiveRecord::Migration[8.0]
  # User-initiated safety reports against another profile. Deliberately separate
  # from blocking (relationship control) and from a photo's moderation `status`:
  # a report is an audit signal for administrative review, and never changes a
  # target's visibility on its own. HookUs photos stay visible after safe
  # processing; reporting is the backstop, not an approval gate.
  def change
    create_table :reports do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :reporter_profile, null: false, foreign_key: false
      t.references :reported_profile, null: false, foreign_key: false
      t.integer :reason, null: false
      t.integer :status, null: false, default: 0
      t.text :note

      t.timestamps
    end

    # At most one open report per reporter -> target keeps repeat submissions
    # idempotent and blunts report spam, while still allowing a fresh report once
    # a prior one is resolved.
    add_index :reports, [ :brand_id, :reporter_profile_id, :reported_profile_id ],
      unique: true,
      where: "status = 0",
      name: "idx_reports_open_pair"
    add_index :reports, [ :brand_id, :status, :created_at ],
      name: "index_reports_on_brand_id_and_status_and_created_at"
    add_index :reports, [ :brand_id, :reported_profile_id ],
      name: "index_reports_on_brand_id_and_reported_profile_id"
    add_check_constraint :reports,
      "reporter_profile_id <> reported_profile_id",
      name: "chk_reports_not_self"
    add_foreign_key :reports, :profiles,
      column: [ :reporter_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_reports_reporter_tenant"
    add_foreign_key :reports, :profiles,
      column: [ :reported_profile_id, :brand_id ],
      primary_key: [ :id, :brand_id ],
      name: "fk_reports_reported_tenant"
  end
end
