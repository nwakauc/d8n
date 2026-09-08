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
    end
  end
end
