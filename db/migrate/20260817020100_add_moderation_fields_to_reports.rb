class AddModerationFieldsToReports < ActiveRecord::Migration[8.0]
  # Decision provenance for a moderated report: who last acted, when, and an
  # optional short resolution note. The immutable audit trail lives in
  # SecurityEvent; these columns hold only the current decision state so the queue
  # and detail views can show it without a separate case-history subsystem.
  def change
    add_reference :reports, :reviewed_by_admin_user, null: true,
      foreign_key: { to_table: :admin_users }
    add_column :reports, :reviewed_at, :datetime
    add_column :reports, :resolution_note, :text
  end
end
