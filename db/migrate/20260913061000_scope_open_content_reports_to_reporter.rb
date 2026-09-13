class ScopeOpenContentReportsToReporter < ActiveRecord::Migration[8.0]
  def up
    remove_index :reports, name: "idx_reports_open_target"
    add_index :reports, %i[brand_id reporter_profile_id target_type target_id],
      unique: true,
      where: "status = 0 AND target_id IS NOT NULL",
      name: "idx_reports_open_target"
  end

  def down
    remove_index :reports, name: "idx_reports_open_target"
    add_index :reports, %i[brand_id target_type target_id],
      unique: true,
      where: "status = 0 AND target_id IS NOT NULL",
      name: "idx_reports_open_target"
  end
end
