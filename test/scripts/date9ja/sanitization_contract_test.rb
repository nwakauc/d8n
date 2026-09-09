# frozen_string_literal: true

require "test_helper"

module Date9ja
  class SanitizationContractTest < ActiveSupport::TestCase
    SCRIPT_DIR = Rails.root.join("scripts/date9ja")

    def sanitizer = File.read(SCRIPT_DIR.join("sanitize_snapshot.sql"))
    def verifier = File.read(SCRIPT_DIR.join("verify_sanitized_snapshot.sql"))
    def signature = File.read(SCRIPT_DIR.join("schema_signature.sql"))
    def contract = File.read(Rails.root.join(
      "docs/migrations/date9ja-to-d8n/AUTHORITATIVE-SNAPSHOT-20260908.md"
    ))

    test "schema v3 is pinned to the authoritative production snapshot rather than HEAD" do
      assert_includes signature, "0b0e2e2b4b6df617558834f859c44750"
      assert_includes signature, "v_expect_cols   int  := 592"
      assert_includes signature, "'exit_attempts'"
      refute_includes signature, "app_launch_notice_at"
      refute_includes signature, "identity_confirmation_pending"
    end

    test "every production lifecycle addition has an explicit sanitization and census contract" do
      %w[
        discovery_restricted_at discovery_restriction_reason discovery_restriction_note
        discovery_restricted_by_id deletion_reason_code deletion_comment exit_attempts
      ].each do |source_object|
        assert_includes contract, source_object
      end
    end

    test "new uncontrolled text and JSON are sanitized and verified" do
      %w[
        discovery_restriction_note deletion_comment exit_attempts.comment
        exit_attempts.final_comment exit_attempts.context
      ].each do |field|
        table, column = field.split(".", 2)
        token = column || table
        assert_includes sanitizer, token
        assert_includes verifier, token
      end
    end

    test "all user-controlled arrays are removed from the shareable snapshot" do
      %w[
        languages_spoken interests relationship_values dealbreakers
        preferred_countries relocation_preferences
      ].each do |column|
        assert_match(/#{column}\s*= '\{\}'::character varying\[\]/, sanitizer)
        assert_includes verifier, "users.#{column}"
      end
    end

    test "sanitizer no longer rejects a correctly sanitized rerun" do
      refute_includes sanitizer, "looks already sanitized"
      %w[signup_source attribution_source attribution_medium attribution_campaign attribution_content].each do |column|
        assert_match(/#{column}\s*= CASE.*?\^bucket_\[0-9\]\+\$/m, sanitizer)
      end
    end
  end
end
