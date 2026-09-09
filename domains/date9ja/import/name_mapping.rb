# frozen_string_literal: true

module Date9ja
  module Import
    # Date9ja-only interpretation of the legacy full_name field. Date9ja stored a
    # single free-text name and displayed it as-is, so every non-empty value is a
    # usable name here: the first whitespace-delimited token is the given name
    # (which also becomes the Date9ja display name), and any remaining tokens are
    # joined as the surname. A one-token name simply has no surname — none is
    # fabricated — and no token is ever discarded.
    module NameMapping
      Outcome = Data.define(:status, :first_name, :last_name) do
        def mapped? = status == :mapped
      end

      module_function

      def call(value)
        tokens = value.to_s.strip.split(/\s+/)
        return Outcome.new(status: :ambiguous, first_name: nil, last_name: nil) if tokens.empty?
        return Outcome.new(status: :ambiguous, first_name: nil, last_name: nil) if tokens.any? { |token| token.length > 100 }

        first, *rest = tokens
        Outcome.new(status: :mapped, first_name: first, last_name: rest.join(" ").presence)
      end
    end
  end
end
