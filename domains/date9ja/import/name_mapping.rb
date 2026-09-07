# frozen_string_literal: true

module Date9ja
  module Import
    # Date9ja-only interpretation of the legacy full_name field. Exactly two
    # whitespace-delimited tokens are the only shape this pass treats as an
    # unambiguous first/last pair. One-token and 3+-token names require member
    # confirmation; a surname is never fabricated and no token is discarded.
    module NameMapping
      Outcome = Data.define(:status, :first_name, :last_name) do
        def mapped? = status == :mapped
      end

      module_function

      def call(value)
        tokens = value.to_s.strip.split(/\s+/)
        return Outcome.new(status: :ambiguous, first_name: nil, last_name: nil) unless tokens.length == 2
        return Outcome.new(status: :ambiguous, first_name: nil, last_name: nil) if tokens.any? { |token| token.length > 100 }

        Outcome.new(status: :mapped, first_name: tokens.first, last_name: tokens.last)
      end
    end
  end
end
