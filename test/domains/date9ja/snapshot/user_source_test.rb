# frozen_string_literal: true

require "test_helper"

module Date9ja
  module Snapshot
    class UserSourceTest < ActiveSupport::TestCase
      test "requires either rows or a connection" do
        assert_raises(ArgumentError) { UserSource.new }
      end

      test "yields UserRecords in deterministic primary-key order" do
        rows = [ { "id" => 3 }, { "id" => 1 }, { "id" => 2 } ].map { |r| base_row.merge(r) }
        source = UserSource.new(rows: rows)

        records = source.to_a
        assert_equal %w[1 2 3], records.map(&:source_id)
        assert(records.all? { |record| record.is_a?(UserRecord) })
      end

      test "the SELECT column list excludes every sensitive/gated column" do
        assert_empty(
          UserSource::SELECTED_COLUMNS & Date9ja::Import::FieldMapping::SENSITIVE_DENYLIST
        )
      end

      test "does not cross unused free-form language values into the record" do
        refute_includes UserSource::SELECTED_COLUMNS, "languages_spoken"
        refute_includes UserRecord.members.map(&:to_s), "languages_spoken"
      end

      test "does not run the schema guard for synthetic rows" do
        # No connection => SchemaGuard is never touched.
        assert_nothing_raised { UserSource.new(rows: [ base_row ]).to_a }
      end

      private

      def base_row
        {
          "id" => 1, "public_id" => "pub-1", "email" => "a@b.example", "phone" => nil,
          "encrypted_password" => "x", "confirmed_at" => nil, "phone_verified_at" => nil,
          "created_at" => nil, "deleted_at" => nil, "suspended_at" => nil, "banned_at" => nil,
          "profile_hidden" => false, "onboarding_completed_at" => nil, "date_of_birth" => nil,
          "gender" => nil, "display_name" => nil, "city" => nil, "country_of_residence" => nil,
          "about_me" => nil, "ideal_partner_description" => nil, "languages_spoken" => nil
        }
      end
    end
  end
end
