# frozen_string_literal: true

module Date9ja
  module Snapshot
    # Read-only adapter for the legacy relationship tables. It normalizes the
    # source's user-oriented foreign keys to the profile-reference contract used
    # by HistoricalGraphImport. Date9ja has no conversations table: one stable
    # conversation identity is derived from each source match id.
    class HistoricalGraphSource
      CONVERSATION_PREFIX = "date9ja-match:"

      def initialize(rows: nil, connection: nil)
        raise ArgumentError, "provide rows: or connection:" if rows.nil? && connection.nil?
        @rows = rows
        @connection = connection
      end

      def likes
        rows(:likes, { liker_id: :liker_profile_id, liked_id: :liked_profile_id }) do |row|
          row[:kind] = { 0 => "like", 1 => "super_like" }.fetch(row[:kind].to_i, row[:kind])
        end
      end
      def passes = rows(:profile_passes, { passer_id: :passer_profile_id, passed_id: :passed_profile_id })
      def matches = rows(:matches, { user_a_id: :profile_a_id, user_b_id: :profile_b_id })
      def blocks = rows(:blocks, { blocker_id: :blocker_profile_id, blocked_id: :blocked_profile_id })
      def reports
        rows(:reports, { reporter_id: :reporter_profile_id, reported_id: :reported_profile_id,
          category: :reason }) do |row|
          row[:reason] = { 0 => "fake_profile", 1 => "scam", 2 => "harassment", 3 => "inappropriate", 4 => "other" }
            .fetch(row[:reason].to_i, row[:reason])
        end
      end

      def conversations
        matches.map do |match|
          { id: conversation_id(match.fetch(:id)), match_id: match.fetch(:id), created_at: match[:created_at] }
        end
      end

      def messages
        rows(:messages, { match_id: :conversation_id, sender_id: :sender_profile_id }) do |row|
          row[:conversation_id] = conversation_id(row[:conversation_id])
          row[:kind] = { 0 => "text", 1 => "voice", 2 => "image", 3 => "video" }.fetch(row[:kind].to_i, row[:kind]) if row.key?(:kind)
          row[:message_type] = row[:kind] if row[:message_type].blank? && row[:kind].present?
        end
      end

      def conversation_id(match_id)
        "#{CONVERSATION_PREFIX}#{match_id}:conversation"
      end

      # Date9ja user ids for seed/demo accounts. A relationship row touching one
      # of these is production-excluded (§5) and HistoricalGraphImport drops it
      # rather than over-importing. Empty for the array-backed test source.
      def excluded_participant_ids
        return Array(@rows[:excluded_participant_ids] || @rows["excluded_participant_ids"]) if @rows
        return [] unless column?("users", "seed_account")

        @connection.exec_query("SELECT id FROM users WHERE seed_account = true ORDER BY id").rows.flatten.map(&:to_s)
      end

      private

      def column?(table, column)
        @connection.exec_query(
          "SELECT 1 FROM information_schema.columns WHERE table_name = '#{table}' AND column_name = '#{column}' LIMIT 1"
        ).any?
      end

      def rows(kind, aliases)
        source_rows(kind).map do |raw|
          row = raw.transform_keys { |key| key.to_s.downcase.to_sym }
          aliases.each { |from, to| row[to] = row.delete(from) if row.key?(from) }
          yield row if block_given?
          row
        end.sort_by { |row| row[:id].to_i }
      end

      def source_rows(kind)
        return Array(@rows.fetch(kind.to_sym, @rows.fetch(kind.to_s, []))) if @rows

        table = kind.to_s
        columns = @connection.exec_query(
          "SELECT column_name FROM information_schema.columns WHERE table_name = '#{table}' ORDER BY ordinal_position"
        ).rows.flatten
        return [] if columns.empty?
        @connection.exec_query("SELECT #{columns.join(', ')} FROM #{table} ORDER BY id").to_a
      end
    end
  end
end
