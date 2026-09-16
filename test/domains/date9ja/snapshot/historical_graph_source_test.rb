require "test_helper"

module Date9ja
  module Snapshot
    class HistoricalGraphSourceTest < ActiveSupport::TestCase
      test "normalizes Date9ja-shaped keys and derives one conversation identity per match" do
        source = HistoricalGraphSource.new(rows: {
          likes: [ { id: 1, liker_id: 10, liked_id: 11 } ],
          matches: [ { id: 2, user_a_id: 10, user_b_id: 11, created_at: Time.utc(2020, 1, 1) } ],
          messages: [ { id: 3, match_id: 2, sender_id: 10, body: "hello", created_at: Time.utc(2020, 1, 2) } ],
          blocks: [ { id: 4, blocker_id: 10, blocked_id: 11 } ],
          reports: [ { id: 5, reporter_id: 10, reported_id: 11, category: "spam" } ]
        })
        assert_equal 10, source.likes.first.fetch(:liker_profile_id)
        assert_equal "date9ja-match:2:conversation", source.conversations.first.fetch(:id)
        assert_equal "date9ja-match:2:conversation", source.messages.first.fetch(:conversation_id)
        assert_equal 10, source.blocks.first.fetch(:blocker_profile_id)
        assert_equal 10, source.reports.first.fetch(:reporter_profile_id)
      end

      test "decodes the Date9ja report category integer to an exact D8N reason and keeps the original" do
        source = HistoricalGraphSource.new(rows: {
          reports: [
            { id: 5, reporter_id: 10, reported_id: 11, category: 3, resolved_at: Time.utc(2025, 1, 1) },
            { id: 6, reporter_id: 10, reported_id: 11, category: 1 }
          ]
        })
        inappropriate, scam = source.reports
        assert_equal "inappropriate_content", inappropriate.fetch(:reason)
        assert_equal 3, inappropriate.fetch(:source_category)
        assert_equal "other", scam.fetch(:reason)
        assert_equal 1, scam.fetch(:source_category)
      end

      test "attaches a PII-free media reference so a blank-body image message keeps its row" do
        source = HistoricalGraphSource.new(rows: {
          matches: [ { id: 2, user_a_id: 10, user_b_id: 11, created_at: Time.utc(2020, 1, 1) } ],
          messages: [ { id: 3, match_id: 2, sender_id: 10, body: nil, kind: 2, created_at: Time.utc(2020, 1, 2) } ],
          message_attachments: [ { message_id: 3, blob_id: 77, checksum: "abc", byte_size: 1234, content_type: "image/jpeg" } ]
        })
        row = source.messages.first
        assert_equal "image", row.fetch(:kind)
        assert_equal "date9ja-blob:77", row.fetch(:attachment_reference)
        assert_equal "abc", row.fetch(:attachment_checksum)
        assert_equal "image/jpeg", row.fetch(:attachment_content_type)
      end
    end
  end
end
