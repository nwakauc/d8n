module Profiles
  # Server-authoritative post-onboarding profile richness. Publication remains
  # owned by Profiles::Completion; this score only drives optional enrichment
  # nudges and can never publish, unpublish, or make onboarding incomplete.
  class RichCompletion
    Result = Data.define(:percent, :level, :missing, :suggestions, :sections)

    SECTION_WEIGHTS = {
      "photos" => 15,
      "about" => 15,
      "interests" => 10,
      "prompts" => 10,
      "work_education" => 10,
      "lifestyle" => 10,
      "relationship_intent" => 10,
      "family_plans" => 5,
      "languages" => 5,
      "personality" => 10
    }.freeze
    SUGGESTION_LABELS = {
      "more_photos" => "Add more photos",
      "bio" => "Add an About me",
      "looking_for" => "Say what you're looking for",
      "interests" => "Add interests",
      "prompt" => "Answer a profile prompt",
      "work_or_education" => "Add work or education",
      "lifestyle" => "Add lifestyle details",
      "relationship_intent" => "Share your relationship intent",
      "family_plans" => "Share your family plans",
      "languages" => "Add languages",
      "personality" => "Add communication or planning style"
    }.freeze
    PHOTO_TARGET = 3
    INTEREST_TARGET = 3
    LIFESTYLE_TARGET = 3
    PERSONALITY_TARGET = 2

    def self.call(profile:)
      new(profile:).call
    end

    def initialize(profile:)
      @profile = profile
    end

    def call
      configured = configured_sections
      return if configured.empty?

      evaluated = configured.index_with { |key| evaluate(key) }
      total_weight = configured.sum { |key| SECTION_WEIGHTS.fetch(key) }
      earned = configured.sum do |key|
        SECTION_WEIGHTS.fetch(key) * evaluated.fetch(key).fetch(:fraction)
      end
      percent = total_weight.zero? ? 100 : (earned.fdiv(total_weight) * 100).round
      missing = evaluated.values.filter_map { |section| section[:suggestion] }

      Result.new(
        percent:,
        level: level(percent),
        missing:,
        suggestions: missing.map { |key| { key:, label: SUGGESTION_LABELS.fetch(key) } },
        sections: evaluated.transform_values do |section|
          { percent: (section.fetch(:fraction) * 100).round, complete: section.fetch(:fraction) == 1.0 }
        end
      )
    end

    private

    attr_reader :profile

    def configured_sections
      @configured_sections ||= profile.brand.profile_completion_requirements.fetch("rich_profile_sections", [])
    end

    def evaluate(key)
      case key
      when "photos" then progress(photo_count, PHOTO_TARGET, "more_photos")
      when "about" then about_progress
      when "interests" then progress(selection_count("interests"), INTEREST_TARGET, "interests")
      when "prompts" then progress(prompt_count, 1, "prompt")
      when "work_education" then binary(work_or_education?, "work_or_education")
      when "lifestyle" then progress(lifestyle_count, LIFESTYLE_TARGET, "lifestyle")
      when "relationship_intent" then binary(selected?("relationship_intent"), "relationship_intent")
      when "family_plans" then progress(selected_group_count(%w[ has_children wants_children ]), 2, "family_plans")
      when "languages" then binary(Profiles::Languages.serialize(profile.languages).any?, "languages")
      when "personality" then progress(personality_count, PERSONALITY_TARGET, "personality")
      else raise ArgumentError, "unsupported rich-profile section: #{key}"
      end
    end

    def about_progress
      completed = [ profile.bio.present?, profile.looking_for_text.present? ].count(true)
      suggestion = profile.bio.blank? ? "bio" : "looking_for"
      progress(completed, 2, suggestion)
    end

    def work_or_education?
      [ profile.occupation, profile.job_title, profile.school_or_institution ].any?(&:present?) ||
        selected?("education_level")
    end

    def lifestyle_count
      scalars = [ profile.smoking, profile.drinking, profile.fitness ].count(&:present?)
      scalars + selected_group_count(%w[ diet pets sleep_schedule travel_frequency ])
    end

    def personality_count
      selected_group_count(%w[ social_style communication_style planning_style ])
    end

    def photo_count
      @photo_count ||= profile.profile_photos.kept.where.not(status: :rejected).count
    end

    def prompt_count
      @prompt_count ||= profile.prompt_answers.kept.joins(:profile_prompt)
        .merge(ProfilePrompt.kept.status_active).count
    end

    def selection_count(group_key)
      selected_options.fetch(group_key, 0)
    end

    def selected?(group_key)
      selection_count(group_key).positive?
    end

    def selected_group_count(group_keys)
      group_keys.count { |key| selected?(key) }
    end

    def selected_options
      @selected_options ||= profile.profile_option_selections.kept
        .joins(:profile_option, :profile_option_group)
        .merge(ProfileOption.kept.status_active)
        .merge(ProfileOptionGroup.kept.status_active)
        .group("profile_option_groups.key")
        .count
        .transform_keys(&:to_s)
    end

    def binary(completed, suggestion)
      { fraction: completed ? 1.0 : 0.0, suggestion: completed ? nil : suggestion }
    end

    def progress(count, target, suggestion)
      fraction = [ count.fdiv(target), 1.0 ].min
      { fraction:, suggestion: fraction == 1.0 ? nil : suggestion }
    end

    def level(percent)
      return "standout" if percent >= 90
      return "good" if percent >= 70
      return "growing" if percent >= 40

      "starter"
    end
  end
end
