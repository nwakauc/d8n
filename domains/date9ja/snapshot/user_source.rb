# frozen_string_literal: true

module Date9ja
  module Snapshot
    # Deterministic reader over the Date9ja `users` table (restored scratch DB).
    #
    #   UserSource.new(connection: Date9ja::Snapshot::Connection.connect!)
    #   UserSource.new(rows: [...])            # synthetic input for tests
    #
    # The SELECT names ONLY the columns this slice may import; a legacy column
    # that is not in SELECTED_COLUMNS is never read, so widening the source
    # schema cannot silently make a new column importable. Ordering is by primary
    # key so a re-run yields the identical sequence.
    class UserSource
      include Enumerable

      SELECTED_COLUMNS = %w[
        id public_id email phone encrypted_password confirmed_at phone_verified_at
        created_at deleted_at suspended_at banned_at profile_hidden
        onboarding_completed_at date_of_birth gender display_name city
        country_of_residence about_me ideal_partner_description
      ].freeze

      def initialize(rows: nil, connection: nil, verify_schema: true)
        raise ArgumentError, "provide rows: or connection:" if rows.nil? && connection.nil?

        @rows = rows
        @connection = connection
        @verify_schema = verify_schema
      end

      def each
        return enum_for(:each) unless block_given?

        SchemaGuard.verify!(connection: @connection) if @connection && @verify_schema

        raw_rows.each { |raw| yield UserRecord.from_raw(raw) }
      end

      private

      def raw_rows
        if @rows
          @rows.map { |row| row.transform_keys(&:to_s) }.sort_by { |row| row.fetch("id").to_i }
        else
          @connection.exec_query(
            "SELECT #{SELECTED_COLUMNS.join(', ')} FROM users ORDER BY id"
          ).to_a
        end
      end
    end
  end
end
