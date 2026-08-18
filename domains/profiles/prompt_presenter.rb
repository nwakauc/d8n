module Profiles
  # Serializes a profile's answered prompts (kept answers to still-active prompts),
  # ordered by position. Shared by the owner and viewer-facing detail serializers so
  # the prompt shape stays identical. Uses in-memory filtering when the association
  # is preloaded to avoid an N+1 on the discovery/detail paths.
  class PromptPresenter
    def self.call(profile:)
      new(profile:).call
    end

    def initialize(profile:)
      @profile = profile
    end

    def call
      answers.sort_by { |answer| [ answer.position, answer.id ] }.map do |answer|
        {
          key: answer.profile_prompt.key,
          prompt: answer.profile_prompt.text,
          answer: answer.answer,
          position: answer.position
        }
      end
    end

    private

    attr_reader :profile

    def answers
      scope = if profile.prompt_answers.loaded?
        profile.prompt_answers.reject(&:deleted_at)
      else
        profile.prompt_answers.kept.ordered.includes(:profile_prompt)
      end

      scope.select { |answer| answer.profile_prompt.status_active? && answer.profile_prompt.deleted_at.nil? }
    end
  end
end
