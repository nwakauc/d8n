require "test_helper"
require_relative "../../../support/hook_test_helpers"

class Api::V1::AiConversationsControllerTest < ActionDispatch::IntegrationTest
  include HookTestHelpers

  FakeProvider = Struct.new(:requests) do
    def complete(system_prompt:, messages:)
      requests << { system_prompt:, messages: }
      Ai::Providers::Openai::Result.new(
        content: "Try a warm, specific question about something they shared.",
        provider: "fake", model: "fake-model", input_tokens: 12, output_tokens: 9, total_tokens: 21
      )
    end
  end

  setup do
    @brand = Brand.create!(slug: "hookus", name: "HookUs")
    BrandDomain.create!(brand: @brand, host: "hookus.test")
    host! "hookus.test"
    @profile = create_member(brand: @brand)
    @profile.update!(bio: "Private profile text that must not leave D8N automatically.")
    @token, = Session.issue!(brand: @brand, user: @profile.user)
  end

  test "persists a private prompt and provider response without automatic profile context" do
    provider = FakeProvider.new([])

    stub_method(Ai::ProviderRegistry, :build, -> { provider }) do
      post ai_messages_path,
        params: { message: "How do I open this conversation?", client_message_id: "opening-1" },
        headers: bearer_headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal true, body.fetch("created")
    assert_equal [ "user", "assistant" ], body.dig("conversation", "messages").map { |message| message.fetch("role") }
    assert_equal 1, AiUsageEvent.count
    assert_equal 1, provider.requests.size
    assert_equal [ "How do I open this conversation?" ], provider.requests.first.fetch(:messages).map { |message| message.fetch(:content) }
    refute_includes provider.requests.first.fetch(:messages).map { |message| message.fetch(:content) }, @profile.bio
  end

  test "same client id is idempotent" do
    provider = FakeProvider.new([])

    stub_method(Ai::ProviderRegistry, :build, -> { provider }) do
      2.times do
        post ai_messages_path,
          params: { message: "Help me write an opener", client_message_id: "same-request" }, headers: bearer_headers
      end
    end

    assert_response :ok
    assert_equal 1, AiConversation.count
    assert_equal 2, AiMessage.count
    assert_equal 1, provider.requests.size
  end

  test "returns provider replies without literal emphasis markers and with readable numbered choices" do
    provider = FakeProvider.new([])
    provider.define_singleton_method(:complete) do |system_prompt:, messages:|
      requests << { system_prompt:, messages: }
      Ai::Providers::Openai::Result.new(
        content: "Start with **Charlotte**. 1. **Charlotte** — shared values. 2. **Riya** — strong fit.",
        provider: "fake", model: "fake-model", input_tokens: 12, output_tokens: 9, total_tokens: 21
      )
    end

    stub_method(Ai::ProviderRegistry, :build, -> { provider }) do
      post ai_messages_path, params: { message: "Who first?" }, headers: bearer_headers
    end

    reply = JSON.parse(response.body).dig("conversation", "messages").last.fetch("content")
    assert_equal "Start with Charlotte.\n1. Charlotte — shared values.\n2. Riya — strong fit.", reply
  end

  test "tells the provider to resolve short follow-ups and avoid repeated boilerplate" do
    provider = FakeProvider.new([])

    stub_method(Ai::ProviderRegistry, :build, -> { provider }) do
      post ai_messages_path, params: { message: "yes, draft it" }, headers: bearer_headers
    end

    prompt = provider.requests.sole.fetch(:system_prompt)
    assert_includes prompt, "Treat a short follow-up"
    assert_includes prompt, "Do not begin every reply"
    assert_includes prompt, "write the opener now"
  end

  test "persists the member-selected assistant language" do
    patch ai_conversation_path,
      params: { language: "pidgin" }, headers: bearer_headers

    assert_response :success
    assert_equal "pidgin", JSON.parse(response.body).dig("conversation", "language")

    patch ai_conversation_path,
      params: { language: "klingon" }, headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "invalid_language", JSON.parse(response.body).fetch("error")
  end

  test "safety language returns local guidance without a provider request" do
    provider = FakeProvider.new([])

    stub_method(Ai::ProviderRegistry, :build, -> { provider }) do
      post ai_messages_path,
        params: { message: "I do not feel safe; he is threatening me." }, headers: bearer_headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "attention", body.dig("conversation", "safety_status")
    assert_includes body.dig("conversation", "messages").last.fetch("content"), "immediate safety"
    assert_empty provider.requests
    assert_equal 0, AiUsageEvent.count
  end

  test "disabled provider returns a stable unavailable error after saving the prompt" do
    previous_provider = ENV.delete("D8N_AI_PROVIDER")

    post ai_messages_path,
      params: { message: "Can you help me decide what to say?", client_message_id: "offline-1" }, headers: bearer_headers

    assert_response :service_unavailable
    assert_equal "assistant_unavailable", JSON.parse(response.body).fetch("error")
    assert_equal 1, AiMessage.where(role: AiMessage.roles.fetch("user")).count
  ensure
    ENV["D8N_AI_PROVIDER"] = previous_provider if previous_provider
  end

  test "date9ja app context serializes the member's own photo without crashing on url generation" do
    date9ja_brand = Brand.create!(slug: "date9ja", name: "Date9ja")
    BrandDomain.create!(brand: date9ja_brand, host: "date9ja.test")
    host! "date9ja.test"
    profile = create_member(brand: date9ja_brand)
    photo = ProfilePhoto.new(brand: date9ja_brand, user: profile.user, profile:, visibility: :visible, status: :approved)
    photo.image.attach(
      io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
      filename: "profile_photo.png", content_type: "image/png"
    )
    photo.save!
    photo.display_image.attach(
      io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
      filename: "display.jpg", content_type: "image/jpeg"
    )
    photo.update!(processing_state: :ready)
    token, = Session.issue!(brand: date9ja_brand, user: profile.user)
    @token = token
    provider = FakeProvider.new([])

    # Regression: Ai::Context::Date9ja.profile_summary serializes the member's
    # own profile through Profiles::PublicSerializer (then strips photos back
    # out) — that serializer signs photo URLs, which raises without
    # ActiveStorage::Current.url_options set on this controller.
    stub_method(Ai::ProviderRegistry, :build, -> { provider }) do
      post ai_messages_path,
        params: { message: "What should I improve on my profile?", client_message_id: "date9ja-1" },
        headers: { "Authorization" => "Bearer #{token}" }
    end

    assert_response :created
    assert_equal 1, provider.requests.size
  end

  test "a brand contract that disables AI returns the configured 404 before provider work" do
    original_capabilities = D8n::Platform::Brands::Hookus::CAPABILITIES
    D8n::Platform::Brands::Hookus.send(:remove_const, :CAPABILITIES)
    D8n::Platform::Brands::Hookus.const_set(:CAPABILITIES, (original_capabilities - [ "ai.dating_assistant" ]).freeze)

    post "/api/v1/ai/assistants/dating_assistant/conversations", headers: bearer_headers

    assert_response :not_found
    assert_equal "assistant_not_configured", JSON.parse(response.body).fetch("error")
  ensure
    D8n::Platform::Brands::Hookus.send(:remove_const, :CAPABILITIES)
    D8n::Platform::Brands::Hookus.const_set(:CAPABILITIES, original_capabilities)
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def conversation_id
    return @conversation_id if defined?(@conversation_id)

    post "/api/v1/ai/assistants/dating_assistant/conversations", headers: bearer_headers
    assert_response :created
    @conversation_id = JSON.parse(response.body).dig("conversation", "id")
  end

  def ai_conversation_path
    "/api/v1/ai/assistants/dating_assistant/conversations/#{conversation_id}"
  end

  def ai_messages_path
    "#{ai_conversation_path}/messages"
  end
end
