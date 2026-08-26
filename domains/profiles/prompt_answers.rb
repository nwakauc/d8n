module Profiles
  # Replace-set writer for a member's prompt answers (mirrors OptionSelections).
  # Accepts an ORDERED array of { key, answer }; order becomes position. Validates
  # against the brand's active prompts, caps the total at
  # ProfilePromptAnswer::MAX_PER_PROFILE, length-limits and strips each answer, and
  # rejects unknown/duplicate prompt keys cleanly. Removing a key soft-deletes its
  # answer; existing answers are updated in place rather than churned.
  class PromptAnswers
    class InvalidAnswer < StandardError
      attr_reader :details

      def initialize(details)
        @details = details
        super("invalid prompt answers")
      end
    end

    MAX_ANSWERS = ProfilePromptAnswer::MAX_PER_PROFILE
    MAX_LENGTH = ProfilePromptAnswer::MAX_ANSWER_LENGTH

    def self.replace!(profile:, answers:)
      new(profile:, answers:).replace!
    end

    def initialize(profile:, answers:)
      @profile = profile
      @answers = answers
    end

    def replace!
      normalized = normalize

      profile.with_lock do
        apply!(normalized)
        Publication.unpublish_if_incomplete!(profile:)
      end

      profile.prompt_answers.kept.ordered.includes(:profile_prompt)
    end

    private

    attr_reader :profile, :answers

    def normalize
      invalid!(base: [ "must be an array" ]) unless answers.is_a?(Array)
      invalid!(base: [ "allows at most #{MAX_ANSWERS} answers" ]) if answers.size > MAX_ANSWERS

      seen = []
      answers.map do |entry|
        hash = entry.respond_to?(:to_h) ? entry.to_h : entry
        invalid!(base: [ "entries must be objects" ]) unless hash.is_a?(Hash)

        key = (hash["key"] || hash[:key]).to_s
        invalid!(key => [ "must be a supported prompt key" ]) unless key.match?(ProfilePrompt::KEY_FORMAT)
        invalid!(key => [ "is duplicated" ]) if seen.include?(key)
        seen << key

        answer = (hash["answer"] || hash[:answer]).to_s.strip
        invalid!(key => [ "must not be blank" ]) if answer.blank?
        invalid!(key => [ "is too long (max #{MAX_LENGTH})" ]) if answer.length > MAX_LENGTH

        { key:, answer: }
      end
    end

    def apply!(entries)
      keys = entries.map { |entry| entry.fetch(:key) }
      prompts = profile.brand.profile_prompts.kept.status_active.where(key: keys).index_by(&:key)
      unknown = keys - prompts.keys
      invalid!(base: [ "contains unsupported prompts: #{unknown.join(', ')}" ]) if unknown.any?

      current = profile.prompt_answers.kept.includes(:profile_prompt).index_by { |answer| answer.profile_prompt.key }
      current.except(*keys).each_value { |answer| answer.update!(deleted_at: Time.current) }

      entries.each_with_index do |entry, position|
        key = entry.fetch(:key)
        if (existing = current[key])
          existing.update!(answer: entry.fetch(:answer), position:)
        else
          profile.prompt_answers.create!(
            brand: profile.brand, profile_prompt: prompts.fetch(key),
            answer: entry.fetch(:answer), position:
          )
        end
      end
    end

    def invalid!(details)
      raise InvalidAnswer, details
    end
  end
end
