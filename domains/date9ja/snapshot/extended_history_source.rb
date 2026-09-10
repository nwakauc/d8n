# frozen_string_literal: true

module Date9ja
  module Snapshot
    # Read-only adapter for every Date9ja operational / member-visible history
    # table that has no dedicated D8N runtime aggregate yet (profile views,
    # daily introductions, explore impressions, notifications + deliveries, push
    # tokens, Aunty Phobie history, community content/moderation, trust ledgers,
    # audit logs, exit attempts, feedback, persona, daily-life, tracked
    # contacts/notes, message reactions) plus the `users` entitlement columns.
    #
    # Each entity has an explicit column allowlist: a legacy column not listed
    # here is never read, so widening the source schema can never silently make
    # a new column importable. Rows are returned as symbol-keyed hashes sorted by
    # primary key, so a re-run yields the identical sequence.
    class ExtendedHistorySource
      # entity => { table:, columns: [...], owner: <fk column resolving the D8N
      # user/profile>, occurred_at: <timestamp column>, status: <status column> }
      ENTITIES = {
        profile_views: {
          table: "profile_views", owner: "viewer_id", counterparty: "viewed_id",
          columns: %w[id viewer_id viewed_id created_at],
          occurred_at: "created_at"
        },
        daily_introductions: {
          table: "daily_introductions", owner: "user_id", counterparty: "introduced_user_id",
          columns: %w[id user_id introduced_user_id status opener_sent_at replied_at
                      reply_unlocked_at created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        explore_impressions: {
          table: "explore_impressions", owner: "user_id", counterparty: "shown_user_id",
          columns: %w[id user_id shown_user_id source created_at],
          occurred_at: "created_at"
        },
        notifications: {
          table: "notifications", owner: "user_id",
          columns: %w[id user_id kind title body read_at data created_at updated_at],
          occurred_at: "created_at"
        },
        notification_deliveries: {
          table: "notification_deliveries", owner: "user_id",
          columns: %w[id notification_id user_id channel status provider error created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        push_tokens: {
          table: "push_tokens", owner: "user_id",
          columns: %w[id user_id platform enabled last_used_at created_at updated_at],
          occurred_at: "created_at"
        },
        aunty_phobie_conversations: {
          table: "aunty_phobie_conversations", owner: "user_id",
          columns: %w[id user_id status last_message_at escalation_status escalated_at
                      escalation_reviewer_id escalation_resolved_at created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        aunty_phobie_messages: {
          table: "aunty_phobie_messages", owner: nil,
          columns: %w[id aunty_phobie_conversation_id role model created_at updated_at],
          occurred_at: "created_at"
        },
        aunty_phobie_usage_events: {
          table: "aunty_phobie_usage_events", owner: "user_id",
          columns: %w[id user_id aunty_phobie_conversation_id kind created_at],
          occurred_at: "created_at"
        },
        community_questions: {
          table: "community_questions", owner: "user_id",
          columns: %w[id user_id title status created_at updated_at published_at],
          occurred_at: "created_at", status: "status"
        },
        community_answers: {
          table: "community_answers", owner: "user_id",
          columns: %w[id user_id community_question_id status created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        community_answer_votes: {
          table: "community_answer_votes", owner: "user_id",
          columns: %w[id user_id community_answer_id created_at],
          occurred_at: "created_at"
        },
        community_events: {
          table: "community_events", owner: "host_id",
          columns: %w[id host_id title status starts_at ends_at created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        community_event_rsvps: {
          table: "community_event_rsvps", owner: "user_id",
          columns: %w[id user_id community_event_id status created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        community_remarks: {
          table: "community_remarks", owner: "user_id",
          columns: %w[id user_id remarkable_type remarkable_id status created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        community_stories: {
          table: "community_stories", owner: "user_id",
          columns: %w[id user_id title status created_at updated_at published_at],
          occurred_at: "created_at", status: "status"
        },
        community_reports: {
          table: "community_reports", owner: "reporter_id",
          columns: %w[id reporter_id reportable_type reportable_id reason status
                      resolved_at resolver_id created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        trust_events: {
          table: "trust_events", owner: "user_id",
          columns: %w[id user_id kind points source_type source_id created_at updated_at],
          occurred_at: "created_at"
        },
        trust_adjustments: {
          table: "trust_adjustments", owner: "user_id",
          columns: %w[id user_id actor_id kind points reason status created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        audit_logs: {
          table: "audit_logs", owner: "target_user_id",
          columns: %w[id kind actor_id target_user_id created_at updated_at],
          occurred_at: "created_at"
        },
        exit_attempts: {
          table: "exit_attempts", owner: "user_id",
          columns: %w[id user_id reason step status resolved_at created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        feedback_items: {
          table: "feedback_items", owner: "user_id",
          columns: %w[id user_id category reviewed_at created_at updated_at],
          occurred_at: "created_at"
        },
        personas: {
          table: "personas", owner: "user_id",
          columns: %w[id user_id name status created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        daily_life_entries: {
          table: "daily_life_entries", owner: "user_id",
          columns: %w[id user_id prompt_key status created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        tracked_contacts: {
          table: "tracked_contacts", owner: "user_id", counterparty: "tracked_user_id",
          columns: %w[id user_id tracked_user_id status label created_at updated_at],
          occurred_at: "created_at", status: "status"
        },
        tracked_contact_notes: {
          table: "tracked_contact_notes", owner: "user_id",
          columns: %w[id user_id tracked_contact_id created_at updated_at],
          occurred_at: "created_at"
        },
        message_reactions: {
          table: "message_reactions", owner: "user_id",
          columns: %w[id message_id user_id emoji reaction created_at updated_at],
          occurred_at: "created_at"
        }
      }.freeze

      ENTITLEMENT_COLUMNS = %w[
        id trust_xp founding_member subscription_status premium_expires_at
      ].freeze

      def initialize(rows: nil, connection: nil)
        raise ArgumentError, "provide rows: or connection:" if rows.nil? && connection.nil?

        @rows = rows&.transform_keys(&:to_sym)
        @connection = connection
      end

      ENTITIES.each_key do |entity|
        define_method(entity) { read(entity) }
      end

      def entitlements
        if @rows
          Array(@rows[:entitlements]).map { |row| row.transform_keys(&:to_sym) }
        else
          @connection.exec_query(
            "SELECT #{ENTITLEMENT_COLUMNS.join(', ')} FROM users ORDER BY id"
          ).to_a.map { |row| row.transform_keys(&:to_sym) }
        end
      end

      private

      def read(entity)
        config = ENTITIES.fetch(entity)
        raw_rows(entity, config).map do |raw|
          row = raw.transform_keys { |key| key.to_s.downcase.to_sym }
          row[:__owner_key] = config[:owner]&.to_sym
          row[:__counterparty_key] = config[:counterparty]&.to_sym
          row[:__occurred_at] = config[:occurred_at]&.to_sym
          row[:__status] = config[:status]&.to_sym
          row
        end.sort_by { |row| row[:id].to_i }
      end

      def raw_rows(entity, config)
        return Array(@rows.fetch(entity, [])) if @rows

        table = config.fetch(:table)
        present = @connection.exec_query(
          "SELECT column_name FROM information_schema.columns WHERE table_name = '#{table}'"
        ).rows.flatten
        selected = config.fetch(:columns) & present
        return [] if selected.empty? || !present.include?("id")

        @connection.exec_query("SELECT #{selected.join(', ')} FROM #{table} ORDER BY id").to_a
      end
    end
  end
end
