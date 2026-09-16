class EnforceCommunityTenantIntegrity < ActiveRecord::Migration[8.0]
  PARENT_TABLES = %i[
    community_questions community_answers community_events community_circles
    community_posts
  ].freeze

  def change
    PARENT_TABLES.each do |table|
      add_index table, %i[id brand_id], unique: true, name: "idx_#{table}_id_brand"
    end
    add_index :community_answers, %i[id community_question_id], unique: true,
      name: "idx_community_answers_id_question"

    tenant_fk :community_questions, %i[author_profile_id brand_id], :profiles, %i[id brand_id],
      "fk_community_questions_author_tenant"
    tenant_fk :community_answers, %i[community_question_id brand_id], :community_questions, %i[id brand_id],
      "fk_community_answers_question_tenant"
    tenant_fk :community_answers, %i[author_profile_id brand_id], :profiles, %i[id brand_id],
      "fk_community_answers_author_tenant"
    tenant_fk :community_events, %i[organizer_profile_id brand_id], :profiles, %i[id brand_id],
      "fk_community_events_organizer_tenant"
    tenant_fk :community_event_rsvps, %i[community_event_id brand_id], :community_events, %i[id brand_id],
      "fk_community_rsvps_event_tenant"
    tenant_fk :community_event_rsvps, %i[profile_id brand_id], :profiles, %i[id brand_id],
      "fk_community_rsvps_profile_tenant"
    tenant_fk :community_circles, %i[creator_profile_id brand_id], :profiles, %i[id brand_id],
      "fk_community_circles_creator_tenant"
    tenant_fk :community_circle_memberships, %i[community_circle_id brand_id], :community_circles, %i[id brand_id],
      "fk_community_memberships_circle_tenant"
    tenant_fk :community_circle_memberships, %i[profile_id brand_id], :profiles, %i[id brand_id],
      "fk_community_memberships_profile_tenant"
    tenant_fk :community_posts, %i[community_circle_id brand_id], :community_circles, %i[id brand_id],
      "fk_community_posts_circle_tenant"
    tenant_fk :community_posts, %i[author_profile_id brand_id], :profiles, %i[id brand_id],
      "fk_community_posts_author_tenant"
    tenant_fk :community_comments, %i[community_post_id brand_id], :community_posts, %i[id brand_id],
      "fk_community_comments_post_tenant"
    tenant_fk :community_comments, %i[author_profile_id brand_id], :profiles, %i[id brand_id],
      "fk_community_comments_author_tenant"
    tenant_fk :community_stories, %i[author_profile_id brand_id], :profiles, %i[id brand_id],
      "fk_community_stories_author_tenant"

    add_foreign_key :community_questions, :community_answers,
      column: %i[selected_answer_id id], primary_key: %i[id community_question_id],
      name: "fk_community_questions_selected_answer"

    %i[community_questions community_answers community_events community_stories community_circles].each do |table|
      add_check_constraint table, "status IN (0, 1, 2, 3)", name: "chk_#{table}_status"
    end
    add_check_constraint :community_questions, "selection_status IN (0, 1, 2)",
      name: "chk_community_questions_selection_status"
    add_check_constraint :community_event_rsvps, "status IN (0, 1)", name: "chk_community_rsvps_status"
    add_check_constraint :community_circle_memberships, "status IN (0, 1)", name: "chk_community_memberships_status"
  end

  private

  def tenant_fk(from, columns, to, primary_keys, name)
    add_foreign_key from, to, column: columns, primary_key: primary_keys, name:
  end
end
