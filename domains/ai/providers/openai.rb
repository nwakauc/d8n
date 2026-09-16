require "net/http"

module Ai
  module Providers
    # OpenAI is the initial adapter because Date9ja already runs it. The rest of
    # D8N depends only on #complete's stable result, so another provider adapter
    # can replace this through D8N_AI_PROVIDER without changing controllers or
    # persisted conversation data.
    class Openai
      API_URL = "https://api.openai.com/v1/chat/completions".freeze
      REQUEST_TIMEOUT = 25
      Result = Data.define(:content, :provider, :model, :input_tokens, :output_tokens, :total_tokens)

      def initialize(api_key: ENV["D8N_AI_OPENAI_API_KEY"], model: ENV.fetch("D8N_AI_OPENAI_MODEL", "gpt-4.1-mini"))
        @api_key = api_key
        @model = model
      end

      def complete(system_prompt:, messages:)
        raise Ai::ProviderUnavailable, "AI provider is unavailable" if api_key.blank?

        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = REQUEST_TIMEOUT
        http.read_timeout = REQUEST_TIMEOUT
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_key}"
        request["Content-Type"] = "application/json"
        request.body = {
          model:,
          max_completion_tokens: 700,
          store: false,
          messages: [ { role: "system", content: system_prompt }, *messages ]
        }.to_json
        response = http.request(request)
        raise Ai::ProviderUnavailable, "AI provider is unavailable" unless response.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(response.body)
        content = parsed.dig("choices", 0, "message", "content").to_s.strip
        raise Ai::ProviderUnavailable, "AI provider is unavailable" if content.blank?

        usage = parsed.fetch("usage", {})
        Result.new(
          content:, provider: "openai", model:,
          input_tokens: usage["prompt_tokens"], output_tokens: usage["completion_tokens"],
          total_tokens: usage["total_tokens"]
        )
      rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET
        raise Ai::ProviderUnavailable, "AI provider is unavailable"
      end

      private

      attr_reader :api_key, :model
    end
  end
end
