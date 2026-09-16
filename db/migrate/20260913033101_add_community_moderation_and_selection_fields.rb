class AddCommunityModerationAndSelectionFields < ActiveRecord::Migration[8.0]
  def change
    %i[community_questions community_answers community_events community_stories community_circles].each do |table|
      add_column table, :published_at, :datetime
      add_column table, :moderation_note, :text
      add_reference table, :reviewed_by_admin_user, foreign_key: { to_table: :admin_users }
      add_column table, :reviewed_at, :datetime
    end

    add_column :community_questions, :selection_status, :integer, null: false, default: 0
    add_column :community_questions, :selection_provider, :string
    add_column :community_questions, :selection_model, :string
    add_check_constraint :community_questions, "closes_at > created_at", name: "chk_community_questions_close_after_create"
    add_check_constraint :community_events, "capacity IS NULL OR capacity > 0", name: "chk_community_events_capacity_positive"
  end
end
