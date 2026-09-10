require "test_helper"

module Date9ja
  module Import
    class HistoricalGraphImportTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        @alice = profile("alice", "woman")
        @bob = profile("bob", "man")
        bind_profile("a", @alice)
        bind_profile("b", @bob)
      end

      test "imports canonical graph, is idempotent, and suppresses notifications" do
        source = HistoricalGraphImport::Source.new(
          likes: [ { id: 1, liker_profile_id: "a", liked_profile_id: "b", created_at: 2.days.ago } ],
          passes: [],
          matches: [ { id: 2, profile_a_id: "a", profile_b_id: "b", created_at: 1.day.ago } ],
          conversations: [ { id: 3, match_id: "2", created_at: 1.day.ago } ],
          messages: [
            { id: 4, conversation_id: "3", sender_profile_id: "a", body: "Historical hello", created_at: 1.hour.ago },
            { id: 5, conversation_id: "3", sender_profile_id: "b", body: "Historical reply", created_at: 30.minutes.ago }
          ],
          blocks: [], reports: []
        )

        assert_no_difference -> { NotificationEvent.count } do
          first = HistoricalGraphImport.call(brand: @brand, source:)
          assert_equal 1, first.counts.fetch("likes.imported")
          assert_equal 1, first.counts.fetch("matches.imported")
          assert_equal 1, first.counts.fetch("conversations.imported")
          assert_equal 2, first.counts.fetch("messages.imported")
        end
        assert_equal [ "Historical hello", "Historical reply" ], Message.order(:created_at).pluck(:body)

        counts = [ Like.count, Match.count, Conversation.count, Message.count, LegacyReference.count ]
        second = HistoricalGraphImport.call(brand: @brand, source:)
        assert_equal counts, [ Like.count, Match.count, Conversation.count, Message.count, LegacyReference.count ]
        assert_equal 2, second.counts.fetch("messages.already_imported")
      end

      test "drops relationship rows that touch a seed/demo account" do
        result = HistoricalGraphImport.call(
          brand: @brand,
          excluded_source_ids: [ "b" ],
          source: HistoricalGraphImport::Source.new(
            likes: [
              { id: 70, liker_profile_id: "a", liked_profile_id: "b", created_at: 2.days.ago },
              { id: 71, liker_profile_id: "b", liked_profile_id: "a", created_at: 2.days.ago }
            ],
            passes: [], matches: [], conversations: [], messages: [], blocks: [], reports: []
          )
        )
        assert_equal 0, Like.count
        assert_equal 2, result.counts.fetch("likes.skipped")
        assert_equal 2, result.reasons.fetch("likes.seed_linked_participant")
      end

      test "the snapshot adapter supplies seed participant ids from the users table" do
        adapter = Date9ja::Snapshot::HistoricalGraphSource.new(rows: {
          excluded_participant_ids: [ "b" ],
          likes: [ { id: 72, liker_id: "a", liked_id: "b", created_at: 1.day.ago } ],
          matches: [], messages: [], blocks: [], reports: []
        })
        result = HistoricalGraphImport.call(brand: @brand, source: adapter)
        assert_equal 1, result.reasons.fetch("likes.seed_linked_participant")
      end

      test "skips rows whose participants were not migrated" do
        result = HistoricalGraphImport.call(
          brand: @brand,
          source: HistoricalGraphImport::Source.new(
            likes: [ { id: 9, liker_profile_id: "missing", liked_profile_id: "b" } ],
            passes: [], matches: [], conversations: [], messages: [], blocks: [], reports: []
          )
        )
        assert_equal 1, result.counts.fetch("likes.skipped")
        assert_equal 1, result.reasons.fetch("likes.participant_not_migrated")
      end

      test "reuses and binds a pre-existing conversation so messages are retained" do
        match = Match.create!(brand: @brand, profile_a: @alice, profile_b: @bob, created_at: 2.days.ago)
        conversation = Conversation.create!(brand: @brand, match:, created_at: 2.days.ago)
        [ @alice, @bob ].each { |profile| conversation.conversation_participants.create!(profile:, user: profile.user, brand: @brand) }
        source = HistoricalGraphImport::Source.new(
          likes: [], passes: [], matches: [ { id: 20, profile_a_id: "a", profile_b_id: "b", created_at: 2.days.ago } ],
          conversations: [ { id: "date9ja-match:20:conversation", match_id: "20", created_at: 2.days.ago } ],
          messages: [ { id: 21, conversation_id: "date9ja-match:20:conversation", sender_profile_id: "a", body: "kept", created_at: 1.day.ago } ],
          blocks: [], reports: []
        )
        HistoricalGraphImport.call(brand: @brand, source:)
        assert_equal conversation, Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "conversation", source_id: "date9ja-match:20:conversation")
        assert_equal "kept", Message.find_by!(body: "kept").body
      end

      test "keeps distinct reports distinct, preserves non-text message kind, and quarantines untimestamped messages" do
        rows = [
          { id: 31, reporter_profile_id: "a", reported_profile_id: "b", target_type: :message, target_id: 100, reason: :spam, created_at: 2.days.ago },
          { id: 32, reporter_profile_id: "a", reported_profile_id: "b", target_type: :message, target_id: 101, reason: :harassment, created_at: 1.day.ago }
        ]
        result = HistoricalGraphImport.call(brand: @brand, source: HistoricalGraphImport::Source.new(
          likes: [], passes: [], matches: [ { id: 50, profile_a_id: "a", profile_b_id: "b", created_at: 2.days.ago } ],
          conversations: [ { id: "date9ja-match:50:conversation", match_id: "50", created_at: 2.days.ago } ], messages: [
            { id: 40, conversation_id: "date9ja-match:50:conversation", sender_profile_id: "a", body: "caption", message_type: "image", attachment_reference: "date9ja-msg:40", created_at: 1.day.ago },
            { id: 41, conversation_id: "date9ja-match:50:conversation", sender_profile_id: "a", body: "text" }
          ], blocks: [], reports: rows))
        assert_equal 2, Report.count
        assert_equal 2, LegacyReference.where(source_entity: "report").count
        image = Message.find_by!(body: "caption")
        assert image.kind_image?
        assert_equal "date9ja-msg:40", image.source_media_reference
        assert_equal 1, result.reasons.fetch("messages.missing_created_at")
      end

      test "preserves native unmatch, unblock, and post-import message state on rerun" do
        source = graph_source(match_id: 60)
        HistoricalGraphImport.call(brand: @brand, source:)
        match = Match.find_by!(brand: @brand, profile_a: @alice, profile_b: @bob)
        conversation = Conversation.find_by!(match:)

        Matching::Unmatch.call(user: @alice.user, brand: @brand, match_public_id: match.public_id)
        HistoricalGraphImport.call(brand: @brand, source:)
        assert match.reload.status_ended?

        block_source = HistoricalGraphImport::Source.new(likes: [], passes: [], matches: [], conversations: [], messages: [],
          blocks: [ { id: 61, blocker_profile_id: "a", blocked_profile_id: "b", created_at: 1.day.ago } ], reports: [])
        HistoricalGraphImport.call(brand: @brand, source: block_source)
        Trust::UnblockProfile.call(user: @alice.user, brand: @brand, target_public_id: @bob.public_id)
        HistoricalGraphImport.call(brand: @brand, source: block_source)
        assert ProfileBlock.find_by!(brand: @brand, blocker_profile: @alice, blocked_profile: @bob).deleted_at.present?

        native = Message.create!(brand: @brand, conversation:, sender_profile: @alice, body: "native", created_at: Time.current)
        HistoricalGraphImport.call(brand: @brand, source:)
        assert_equal "native", native.reload.body
      end

      test "the snapshot adapter normalizes Date9ja rows into the importer contract" do
        adapter = Date9ja::Snapshot::HistoricalGraphSource.new(rows: {
          likes: [ { id: 1, liker_id: "a", liked_id: "b", created_at: 1.day.ago } ],
          matches: [ { id: 2, user_a_id: "a", user_b_id: "b", created_at: 1.day.ago } ],
          messages: [ { id: 3, match_id: 2, sender_id: "a", body: "hello", message_type: "text", created_at: 1.day.ago } ],
          blocks: [], reports: []
        })
        result = HistoricalGraphImport.call(brand: @brand, source: adapter)
        assert_equal 1, result.counts.fetch("likes.imported")
        assert_equal 1, result.counts.fetch("matches.imported")
        assert_equal 1, result.counts.fetch("conversations.imported")
        assert_equal 1, result.counts.fetch("messages.imported")
      end

      private

      def profile(name, gender)
        user = User.create!
        membership = BrandMembership.create!(brand: @brand, user:)
        Profile.create!(brand: @brand, user:, brand_membership: membership,
          display_name: name, birthdate: 30.years.ago.to_date, gender:)
      end

      def bind_profile(id, profile)
        Migration::ReferenceMap.bind!(source_system: "date9ja", source_entity: "profile", source_id: id,
          destination: profile, brand: @brand, importer_version: "fixture")
      end

      def graph_source(match_id:)
        conversation_id = "date9ja-match:#{match_id}:conversation"
        HistoricalGraphImport::Source.new(likes: [], passes: [],
          matches: [ { id: match_id, profile_a_id: "a", profile_b_id: "b", created_at: 2.days.ago } ],
          conversations: [ { id: conversation_id, match_id:, created_at: 2.days.ago } ],
          messages: [ { id: match_id + 1, conversation_id:, sender_profile_id: "a", body: "history", created_at: 1.day.ago } ],
          blocks: [], reports: [])
      end
    end
  end
end
