require "test_helper"

module Profiles
  class PromptAnswersTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      HookusProfileCatalog.install!(brand: @brand)
      user = User.create!
      membership = BrandMembership.create!(brand: @brand, user:)
      @profile = Profile.create!(brand: @brand, user:, brand_membership: membership)
    end

    test "replaces the ordered answer set and assigns positions" do
      PromptAnswers.replace!(profile: @profile, answers: [
        { "key" => "perfect_night", "answer" => "Good food and music." },
        { "key" => "toxic_trait", "answer" => "Always late." }
      ])

      answers = @profile.prompt_answers.kept.ordered.includes(:profile_prompt)
      assert_equal %w[ perfect_night toxic_trait ], answers.map { |a| a.profile_prompt.key }
      assert_equal [ 0, 1 ], answers.map(&:position)

      # Re-running removes a dropped key and updates an existing one in place.
      PromptAnswers.replace!(profile: @profile, answers: [
        { "key" => "perfect_night", "answer" => "Updated answer." }
      ])
      remaining = @profile.prompt_answers.kept.includes(:profile_prompt)
      assert_equal %w[ perfect_night ], remaining.map { |a| a.profile_prompt.key }
      assert_equal "Updated answer.", remaining.sole.answer
    end

    test "rejects unknown keys, duplicates, blanks, over-length, and the cap" do
      assert_raises(PromptAnswers::InvalidAnswer) do
        PromptAnswers.replace!(profile: @profile, answers: [ { "key" => "nope_not_real", "answer" => "x" } ])
      end
      assert_raises(PromptAnswers::InvalidAnswer) do
        PromptAnswers.replace!(profile: @profile, answers: [
          { "key" => "perfect_night", "answer" => "a" }, { "key" => "perfect_night", "answer" => "b" }
        ])
      end
      assert_raises(PromptAnswers::InvalidAnswer) do
        PromptAnswers.replace!(profile: @profile, answers: [ { "key" => "perfect_night", "answer" => "   " } ])
      end
      assert_raises(PromptAnswers::InvalidAnswer) do
        PromptAnswers.replace!(profile: @profile, answers: [
          { "key" => "perfect_night", "answer" => "a" * (ProfilePromptAnswer::MAX_ANSWER_LENGTH + 1) }
        ])
      end
      too_many = @brand.profile_prompts.kept.status_active.ordered.limit(ProfilePromptAnswer::MAX_PER_PROFILE + 1)
        .map { |prompt| { "key" => prompt.key, "answer" => "ok" } }
      assert_raises(PromptAnswers::InvalidAnswer) do
        PromptAnswers.replace!(profile: @profile, answers: too_many)
      end
    end

    test "strips answers and enforces per-profile uniqueness at the model" do
      PromptAnswers.replace!(profile: @profile, answers: [ { "key" => "perfect_night", "answer" => "  spaced  " } ])
      assert_equal "spaced", @profile.prompt_answers.kept.sole.answer

      duplicate = ProfilePromptAnswer.new(
        brand: @brand, profile: @profile,
        profile_prompt: @brand.profile_prompts.kept.find_by!(key: "perfect_night"), answer: "again"
      )
      assert_not duplicate.valid?
    end
  end
end
