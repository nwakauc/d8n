require "test_helper"

module Date9ja
  module Import
    class ExtendedHistoryImportTest < ActiveSupport::TestCase
      setup do
        @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
        @alice = profile("alice", "woman")
        @bob = profile("bob", "man")
        bind(:user, "1", @alice.user)
        bind(:user, "2", @bob.user)
        bind(:profile, "1", @alice)
        bind(:profile, "2", @bob)
      end

      test "routes operational history to the ledger, is idempotent, and filters sensitive keys" do
        source = Snapshot::ExtendedHistorySource.new(rows: {
          profile_views: [ { id: 10, viewer_id: 1, viewed_id: 2, created_at: 2.days.ago } ],
          notifications: [ { id: 11, user_id: 2, kind: "match", title: "New match", read_at: nil,
                             auth_token: "SECRET", created_at: 1.day.ago } ],
          push_tokens: [ { id: 12, user_id: 1, platform: "ios", device_token: "abc", created_at: 3.days.ago } ],
          aunty_phobie_conversations: [ { id: 13, user_id: 1, status: "open", created_at: 4.days.ago } ],
          community_questions: [ { id: 14, user_id: 2, title: "Q?", status: "published", created_at: 5.days.ago } ]
        })

        assert_no_difference -> { NotificationEvent.count } do
          first = ExtendedHistoryImport.call(brand: @brand, source:)
          assert_equal 1, first.reconciliation.count(:profile_views, :imported)
          assert_equal 1, first.reconciliation.count(:notifications, :imported)
        end

        assert_equal 5, Date9jaHistoryRecord.count
        notification = Date9jaHistoryRecord.find_by!(source_entity: "notifications", source_id: "11")
        assert_equal @bob.user, notification.user
        assert_not notification.payload.key?("auth_token")
        assert_equal "match", notification.payload["kind"]
        assert_not Date9jaHistoryRecord.find_by!(source_entity: "push_tokens", source_id: "12").payload.key?("device_token")

        second = ExtendedHistoryImport.call(brand: @brand, source:)
        assert_equal 5, Date9jaHistoryRecord.count
        assert_equal 1, second.reconciliation.count(:profile_views, :already_imported)
      end

      test "skips rows whose owner was not migrated" do
        source = Snapshot::ExtendedHistorySource.new(rows: {
          profile_views: [ { id: 20, viewer_id: 999, viewed_id: 2, created_at: 1.day.ago } ]
        })
        result = ExtendedHistoryImport.call(brand: @brand, source:)
        assert_equal 1, result.reconciliation.count(:profile_views, :skipped)
        assert_equal 0, Date9jaHistoryRecord.count
      end

      test "imports message reactions into the canonical model and binds them" do
        match = Match.create!(brand: @brand, profile_a: @alice, profile_b: @bob, created_at: 2.days.ago)
        conversation = Conversation.create!(brand: @brand, match:, created_at: 2.days.ago)
        message = Message.create!(brand: @brand, conversation:, sender_profile: @alice, body: "hi", created_at: 1.day.ago)
        bind(:message, "5", message)

        source = Snapshot::ExtendedHistorySource.new(rows: {
          message_reactions: [ { id: 30, message_id: 5, user_id: 2, emoji: "❤️", created_at: 1.hour.ago } ]
        })
        result = ExtendedHistoryImport.call(brand: @brand, source:)
        assert_equal 1, result.reconciliation.count(:message_reactions, :imported)
        reaction = MessageReaction.sole
        assert_equal [ message, @bob, "❤️" ], [ reaction.message, reaction.reactor_profile, reaction.emoji ]

        assert_equal 1, ExtendedHistoryImport.call(brand: @brand, source:).reconciliation.count(:message_reactions, :already_imported)
        assert_equal 1, MessageReaction.count
      end

      test "preserves founding-member / trust-xp entitlement onto private user metadata" do
        source = Snapshot::ExtendedHistorySource.new(rows: {
          entitlements: [
            { id: 1, founding_member: true, trust_xp: 240, subscription_status: "free", premium_expires_at: nil },
            { id: 2, founding_member: false, trust_xp: 0 }
          ]
        })
        result = ExtendedHistoryImport.call(brand: @brand, source:)
        assert_equal 2, result.reconciliation.count(:entitlements, :imported)
        assert_equal true, @alice.user.reload.metadata.dig("date9ja", "founding_member")
        assert_equal 240, @alice.user.metadata.dig("date9ja", "trust_xp")

        assert_equal 2, ExtendedHistoryImport.call(brand: @brand, source:).reconciliation.count(:entitlements, :already_imported)
      end

      test "links both sides of a two-party row and binds the ledger record" do
        source = Snapshot::ExtendedHistorySource.new(rows: {
          profile_views: [ { id: 40, viewer_id: 1, viewed_id: 2, created_at: 1.day.ago } ],
          daily_introductions: [ { id: 41, user_id: 1, introduced_user_id: 999, status: "sent", created_at: 1.day.ago } ]
        })
        ExtendedHistoryImport.call(brand: @brand, source:)

        view = Date9jaHistoryRecord.find_by!(source_entity: "profile_views", source_id: "40")
        assert_equal true, view.payload["counterparty_migrated"]
        assert_equal @bob.public_id, view.payload["counterparty_ref"]
        assert_equal view, Migration::ReferenceMap.resolved(source_system: "date9ja", source_entity: "profile_views", source_id: "40")

        intro = Date9jaHistoryRecord.find_by!(source_entity: "daily_introductions", source_id: "41")
        assert_equal false, intro.payload["counterparty_migrated"]
      end

      test "reconciles imported trust-event points against the entitlement trust_xp total" do
        source = Snapshot::ExtendedHistorySource.new(rows: {
          entitlements: [ { id: 1, trust_xp: 30 }, { id: 2, trust_xp: 12 } ],
          trust_events: [
            { id: 50, user_id: 1, kind: "verified", points: 30, created_at: 3.days.ago },
            { id: 51, user_id: 2, kind: "reported", points: 12, created_at: 2.days.ago }
          ]
        })
        metrics = ExtendedHistoryImport.call(brand: @brand, source:).reconciliation.to_h.fetch("metrics")
        assert_equal 42, metrics["trust_event_points_total"]
        assert_equal 42, metrics["entitlement_trust_xp_total"]
        assert_equal 0, metrics["trust_xp_delta"]
      end

      private

      def profile(name, gender)
        user = User.create!
        membership = BrandMembership.create!(brand: @brand, user:)
        Profile.create!(brand: @brand, user:, brand_membership: membership,
          display_name: name, birthdate: 30.years.ago.to_date, gender:)
      end

      def bind(entity, source_id, destination)
        args = { source_system: "date9ja", source_entity: entity.to_s, source_id:,
                 destination:, importer_version: "fixture" }
        args[:brand] = @brand unless destination.is_a?(User)
        Migration::ReferenceMap.bind!(**args)
      end
    end
  end
end
