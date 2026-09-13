module Ai
  class ProviderUnavailable < StandardError; end

  class ConversationService
    HISTORY_LIMIT = 12

    class InvalidMessage < StandardError; end
    class InvalidLanguage < StandardError; end
    class ConversationUnavailable < StandardError; end
    class ConversationNotFound < StandardError; end

    Result = Data.define(:conversation, :created)

    def initialize(user:, brand:, assistant_key:, provider: nil)
      @user = user
      @brand = brand
      @assistant_key = assistant_key.to_s
      @provider = provider
    end

    def create_conversation!(language: "english")
      raise InvalidLanguage unless AiConversation::LANGUAGES.include?(language.to_s)

      AiConversation.create!(brand:, brand_membership: membership, assistant_key:, language: language.to_s, status: :active)
    end

    def conversation!(id:)
      conversation_scope.find(id)
    rescue ActiveRecord::RecordNotFound
      raise ConversationNotFound, "conversation is unavailable"
    end

    def history
      conversation_scope.recent_first.includes(:ai_messages).to_a
    end

    def update_language!(id:, language:)
      conversation = conversation!(id:)
      update_language(conversation:, language:)
      conversation
    end

    def send_message!(id:, content:, client_message_id: nil, language: nil)
      content = content.to_s.strip
      raise InvalidMessage, "message is blank" if content.blank?
      raise InvalidMessage, "message is too long" if content.length > AiMessage::MAX_CONTENT_LENGTH

      conversation = conversation!(id:)
      update_language(conversation:, language:) if language.present?
      existing = conversation.ai_messages.find_by(client_message_id: client_message_id) if client_message_id.present?
      created = existing.nil?
      user_message = existing || conversation.ai_messages.create!(role: :user, content:, client_message_id:)
      # A provider outage deliberately leaves the member's prompt persisted.
      # Retrying the same client id resumes that pending prompt instead of
      # duplicating it; a completed prompt remains idempotent.
      return Result.new(conversation:, created: false) if !created && assistant_reply_exists_after?(conversation:, user_message:)
      if SafetyTriage.requires_immediate_response?(content)
        conversation.ai_messages.create!(role: :assistant, content: SafetyTriage::RESPONSE,
          provider: "d8n_safety", model: "safety_triage_v1")
        conversation.update!(safety_status: :attention, last_message_at: Time.current)
      else
        response = provider.complete(system_prompt: system_prompt(conversation:), messages: provider_messages(conversation))
        conversation.ai_messages.create!(role: :assistant, content: ResponseFormatter.call(response.content),
          provider: response.provider, model: response.model)
        record_usage!(conversation:, user_message:, response:)
        conversation.update!(last_message_at: Time.current)
      end
      Result.new(conversation:, created:)
    rescue ActiveRecord::RecordNotUnique
      Result.new(conversation:, created: false)
    end

    private

    attr_reader :user, :brand, :assistant_key

    def provider
      @provider ||= ProviderRegistry.build
    rescue ProviderRegistry::ConfigurationError
      raise ProviderUnavailable, "AI provider is unavailable"
    end

    def membership
      @membership ||= BrandMembership.kept.active.find_by(user:, brand:) ||
        raise(ConversationUnavailable, "assistant is unavailable")
    end

    def conversation_scope
      raise ConversationUnavailable, "assistant is unavailable" unless AiConversation::ASSISTANT_KEYS.include?(assistant_key)

      AiConversation.kept.where(brand:, brand_membership: membership, assistant_key:)
    end

    def provider_messages(conversation)
      context_message = context.empty? ? [] : [ {
        role: "user",
        content: "Trusted Date9ja app context (not member-authored): #{context.to_json}"
      } ]
      context_message + conversation.ai_messages.order(created_at: :desc, id: :desc).limit(HISTORY_LIMIT).reverse.map do |message|
        { role: message.role, content: message.content }
      end
    end

    def context
      @context ||= Context.for(user:, brand:, membership:)
    end

    def update_language(conversation:, language:)
      raise InvalidLanguage unless AiConversation::LANGUAGES.include?(language.to_s)

      conversation.update!(language: language.to_s)
    end

    def assistant_reply_exists_after?(conversation:, user_message:)
      conversation.ai_messages.where("created_at >= ?", user_message.created_at).role_assistant.exists?
    end

    def record_usage!(conversation:, user_message:, response:)
      AiUsageEvent.create!(
        brand:, brand_membership: membership, ai_conversation: conversation,
        provider: response.provider, model: response.model,
        input_tokens: response.input_tokens, output_tokens: response.output_tokens, total_tokens: response.total_tokens,
        status: :completed,
        request_key: Identity::HmacDigest.call(purpose: "ai-usage", value: "#{conversation.id}:#{user_message.id}")
      )
    end

    def system_prompt(conversation:)
      <<~PROMPT
        You are D8N's helpful, warm, practical assistant. Members may chat with you about anything: everyday decisions, relationships, work, writing, ideas, or Date9ja. For Date9ja questions, help them understand their profile, today's introductions, compatibility, openers, boundaries, and next steps. Do not make a choice for them; explain trade-offs and encourage their agency.
        Reply primarily in #{language_label(conversation.language)}. If the member writes in another language, follow their latest language. The client renders plain text, not Markdown: never use asterisks, hashes, tables, or Markdown formatting. Keep replies short and mobile-readable. When comparing introductions, start with one direct recommendation, then put each person on a separate numbered line, followed by a short next step. Never force slang.
        Maintain a coherent conversation. Do not begin every reply with "I'm here", "I'm here for you", "I'm here to help", or a generic greeting. Do not repeat introductions, scores, or advice already given unless the member asks to revisit them. Treat a short follow-up such as "yes", "do it", "draft it", or "check again" as an answer to your immediately preceding question or offer. Execute the requested action directly before asking any optional follow-up. For example, when you offered to draft an opener and the member says yes, write the opener now; do not ask them to choose again. If a referenced person is clear from the preceding turn, use that person; otherwise give the best useful draft and state the assumption briefly.
        You may use only the trusted D8N app context supplied in this request plus the member's AI chat. Use app context only when relevant. Never claim to have read member-to-member messages, hidden profile fields, media, precise location, verification evidence, Trust data, or anything outside that context.
        Do not reveal private data, impersonate a human, make moderation decisions, or promise that D8N will take an action. If immediate safety, coercion, self-harm, fraud, or abuse arises, encourage local emergency help, trusted support, and D8N reporting/blocking tools.
        Do not provide professional medical, legal, or financial advice. Be honest about uncertainty and never pressure the member to continue a relationship.
      PROMPT
    end

    def language_label(language)
      {
        "english" => "English", "pidgin" => "Nigerian Pidgin", "igbo" => "Igbo",
        "yoruba" => "Yoruba", "hausa" => "Hausa", "french" => "French"
      }.fetch(language, "English")
    end
  end
end
