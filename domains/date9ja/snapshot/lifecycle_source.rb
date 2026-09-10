# frozen_string_literal: true

module Date9ja
  module Snapshot
    # Read-only adapter for the Date9ja lifecycle / moderation columns on
    # `users`. It reads ONLY the enumerated deletion / suspension / ban /
    # discovery-restriction columns — never a credential or contact column — so
    # the lifecycle pass can preserve operator context (reasons, notes, actors,
    # timestamps) for both retained and soft-deleted members without resurrecting
    # a deleted account.
    class LifecycleSource
      COLUMNS = %w[
        id public_id created_at deleted_at deletion_reason deletion_reason_code deletion_comment
        suspended_at suspension_reason banned_at ban_reason flagged_for_moderation_at
        discovery_restricted_at discovery_restricted_by_id discovery_restriction_reason
        discovery_restriction_note
      ].freeze

      def initialize(rows: nil, connection: nil)
        raise ArgumentError, "provide rows: or connection:" if rows.nil? && connection.nil?

        @rows = rows
        @connection = connection
      end

      def users
        raw =
          if @rows
            @rows.map { |row| row.transform_keys(&:to_s) }
          else
            @connection.exec_query("SELECT #{COLUMNS.join(', ')} FROM users ORDER BY id").to_a
          end
        raw.map { |row| row.transform_keys(&:to_sym) }.sort_by { |row| row[:id].to_i }
      end
    end
  end
end
