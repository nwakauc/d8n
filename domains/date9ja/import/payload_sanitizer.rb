# frozen_string_literal: true

module Date9ja
  module Import
    # Shared, deterministic scrubber for the JSON payload persisted on
    # Date9jaHistoryRecord. Legacy operational rows can carry credentials,
    # tokens, or raw contact data in loosely-typed columns; this drops keys that
    # look sensitive and normalises times to ISO-8601 so the ledger payload is
    # safe to serialize and log. It never inspects values, only key names.
    module PayloadSanitizer
      # Substring match: any key containing one of these is dropped.
      SENSITIVE_KEY_FRAGMENTS = %w[
        password secret token otp passcode reset_digest confirmation
        msisdn ip_address api_key access_key signature credential
      ].freeze

      # Exact key match (after downcase): dropped only when the whole key equals
      # one of these, so `author_id` / `phone_verified` style keys survive.
      SENSITIVE_KEY_NAMES = %w[
        email phone phone_number email_address raw_phone raw_email
      ].freeze

      module_function

      def call(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), result|
            next if sensitive_key?(key)

            result[key.to_s] = call(child)
          end
        when Array
          value.map { |child| call(child) }
        when Time, Date, DateTime
          value.iso8601
        else
          value
        end
      end

      def sensitive_key?(key)
        name = key.to_s.downcase
        SENSITIVE_KEY_NAMES.include?(name) ||
          SENSITIVE_KEY_FRAGMENTS.any? { |fragment| name.include?(fragment) }
      end
    end
  end
end
