require "test_helper"

# Proves migrated Date9ja history is usable by the committed Core Dating Loop:
# legacy source rows -> snapshot adapter -> historical importer -> canonical D8N
# graph -> the SAME public HTTP endpoints a native member uses -> a new native
# message. Nothing canonical is created by hand after the import, and no
# migration class is called once the HTTP journey begins.
class Api::V1::Date9jaHistoricalConversationJourneyTest < ActionDispatch::IntegrationTest
  SOURCE_MATCH_ID = 900

  setup do
    @brand = Brands::Date9jaInstaller.call(hosts: [ "date9ja.test" ])
    @alice = create_profile(gender: "woman", interested_in: [ "man" ], age: 30)
    @bob = create_profile(gender: "man", interested_in: [ "woman" ], age: 32)
    bind_profile("a", @alice)
    bind_profile("b", @bob)

    @matched_at = 30.days.ago.change(usec: 0)
    @hello_at = 20.days.ago.change(usec: 0)
    @reply_at = 10.days.ago.change(usec: 0)

    @source = Date9ja::Snapshot::HistoricalGraphSource.new(rows: {
      likes: [], profile_passes: [], blocks: [], reports: [],
      matches: [ { id: SOURCE_MATCH_ID, user_a_id: "a", user_b_id: "b", created_at: @matched_at } ],
      messages: [
        { id: 901, match_id: SOURCE_MATCH_ID, sender_id: "a", message_type: "text",
          body: "Historical hello", created_at: @hello_at },
        { id: 902, match_id: SOURCE_MATCH_ID, sender_id: "b", message_type: "text",
          body: "Historical reply", created_at: @reply_at }
      ]
    })

    # Historical persistence must be silent: no user-facing event for backfilled
    # rows. The native HTTP message later in this test is free to notify normally.
    assert_no_difference -> { NotificationEvent.count } do
      result = Date9ja::Import::HistoricalGraphImport.call(brand: @brand, source: @source)
      assert_equal 1, result.counts.fetch("matches.imported")
      assert_equal 1, result.counts.fetch("conversations.imported")
      assert_equal 2, result.counts.fetch("messages.imported")
    end

    @alice_token, = Session.issue!(brand: @brand, user: @alice.user, credential: verified_credential(@alice.user, "alice@example.test"))
    @bob_token, = Session.issue!(brand: @brand, user: @bob.user, credential: verified_credential(@bob.user, "bob@example.test"))
    host! "date9ja.test"
  end

  test "migrated history is listed, read, extended, and survives a rerun through the normal Date9ja API" do
    # --- historical match is visible on the normal match endpoint ---
    get "/api/v1/matches", headers: bearer_headers(@alice_token)
    assert_response :success
    matches = JSON.parse(response.body).fetch("matches")
    assert_equal 1, matches.length
    match_payload = matches.sole
    assert_equal @bob.public_id, match_payload.dig("profile", "id")
    assert_equal @matched_at.iso8601, match_payload.fetch("matched_at")
    # No migration representation leaks into the member-facing contract.
    assert_equal %w[id matched_at profile], match_payload.keys.sort
    match_public_id = match_payload.fetch("id")

    # --- historical conversation is visible on the normal conversation endpoint ---
    get "/api/v1/conversations", headers: bearer_headers(@alice_token)
    assert_response :success
    conversations = JSON.parse(response.body).fetch("conversations")
    assert_equal 1, conversations.length
    conversation_payload = conversations.sole
    assert_equal match_public_id, conversation_payload.fetch("match_id")
    assert_equal @bob.public_id, conversation_payload.dig("profile", "id")
    conversation_id = conversation_payload.fetch("id")

    # The runtime resolved the very record the importer bound, not a new one.
    imported_conversation = Migration::ReferenceMap.resolved(
      source_system: "date9ja", source_entity: "conversation",
      source_id: @source.conversation_id(SOURCE_MATCH_ID)
    )
    assert_equal imported_conversation.public_id, conversation_id

    # --- historical messages read back in the API's canonical newest-first order ---
    get "/api/v1/conversations/#{conversation_id}/messages", headers: bearer_headers(@alice_token)
    assert_response :success
    history = JSON.parse(response.body).fetch("messages")
    assert_equal [ "Historical reply", "Historical hello" ], history.pluck("body")
    assert_equal [ @bob.public_id, @alice.public_id ], history.pluck("sender_id")
    assert_equal [ @reply_at.iso8601, @hello_at.iso8601 ], history.pluck("created_at")

    # --- a new native message goes through the ordinary runtime path ---
    post "/api/v1/conversations/#{conversation_id}/messages",
      headers: bearer_headers(@alice_token), params: { body: "New D8N message" }
    assert_response :created
    native_public_id = JSON.parse(response.body).dig("message", "id")

    # --- the peer reads history and the new message together ---
    get "/api/v1/conversations/#{conversation_id}/messages", headers: bearer_headers(@bob_token)
    assert_response :success
    thread = JSON.parse(response.body).fetch("messages")
    assert_equal [ "New D8N message", "Historical reply", "Historical hello" ], thread.pluck("body")
    assert_equal [ @alice.public_id, @bob.public_id, @alice.public_id ], thread.pluck("sender_id")

    # --- rerunning the historical import leaves native state untouched ---
    native = Message.find_by!(public_id: native_public_id)
    native_attributes = native.attributes
    reference_bindings = LegacyReference.for_source("date9ja").order(:id)
      .pluck(:source_entity, :source_id, :destination_type, :destination_id)

    assert_no_difference [ -> { NotificationEvent.count }, -> { Match.count },
                           -> { Conversation.count }, -> { Message.count } ] do
      rerun = Date9ja::Import::HistoricalGraphImport.call(brand: @brand, source: @source)
      assert_equal 1, rerun.counts.fetch("matches.already_imported")
      assert_equal 1, rerun.counts.fetch("conversations.already_imported")
      assert_equal 2, rerun.counts.fetch("messages.already_imported")
    end

    assert_equal native_attributes, native.reload.attributes
    assert_equal reference_bindings, LegacyReference.for_source("date9ja").order(:id)
      .pluck(:source_entity, :source_id, :destination_type, :destination_id)

    # The peer's view is unchanged after the rerun.
    get "/api/v1/conversations/#{conversation_id}/messages", headers: bearer_headers(@bob_token)
    assert_response :success
    assert_equal thread, JSON.parse(response.body).fetch("messages")
  end

  private

  def create_profile(gender:, interested_in:, age:)
    user = User.create!
    membership = BrandMembership.create!(brand: @brand, user:)
    profile = Profile.create!(
      brand: @brand, user:, brand_membership: membership, display_name: "Member",
      gender:, birthdate: age.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand: @brand, user:, profile:, min_age: 25, max_age: 40, interested_in:)
    profile
  end

  # Date9ja gates interaction (not visibility) on a verified login identifier.
  def verified_credential(user, email)
    identifier = IdentityIdentifier.create!(
      user:, kind: :email, normalized_value: email, verified_at: Time.current
    )
    Credential.create!(user:, identity_identifier: identifier, kind: :password, status: :active)
  end

  def bind_profile(source_id, profile)
    Migration::ReferenceMap.bind!(
      source_system: "date9ja", source_entity: "profile", source_id:,
      destination: profile, brand: @brand, importer_version: "fixture"
    )
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
