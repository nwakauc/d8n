require "test_helper"

module Profiles
  class DetailSerializerTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "hookus", name: "HookUs")
      HookusProfileCatalog.install!(brand: @brand)
      @viewer = build_profile
      @target = build_profile(
        company_name: "Secret Corp", looking_for_text: "Someone fun",
        languages: [ { "code" => "en", "proficiency" => "fluent", "primary" => true } ]
      )
      OptionSelections.replace!(profile: @target, selections: {
        "interests" => %w[ foodie travel ],
        "physical_affection" => %w[ high ]
      })
      PromptAnswers.replace!(profile: @target, answers: [ { "key" => "perfect_night", "answer" => "Live music." } ])
    end

    test "exposes rich sections but never company_name or matches_only groups without a match" do
      payload = DetailSerializer.call(profile: @target, viewer: @viewer)

      assert_equal "Someone fun", payload.fetch(:looking_for_text)
      assert_equal "en", payload.fetch(:languages).first.fetch(:code)
      assert_equal %w[ foodie travel ], payload.fetch(:options).fetch("interests")
      assert_equal %w[ foodie travel ], payload.fetch(:interests).map { |i| i.fetch(:slug) }
      assert_equal "food", payload.fetch(:interests).find { |i| i.fetch(:slug) == "foodie" }.fetch(:category)
      assert_equal [ "Live music." ], payload.fetch(:prompts).map { |p| p.fetch(:answer) }

      # company_name is owner-only; matches_only group hidden without a match.
      assert_not payload.key?(:company_name)
      assert_not payload.fetch(:options).key?("physical_affection")
    end

    test "reveals matches_only groups only for an active match" do
      first_id, second_id = Match.canonical_pair(@viewer.id, @target.id)
      match = Match.create!(brand: @brand, profile_a_id: first_id, profile_b_id: second_id)

      payload = DetailSerializer.call(profile: @target, viewer: @viewer)
      assert_equal %w[ high ], payload.fetch(:options).fetch("physical_affection")

      # An ended match no longer reveals sensitive groups.
      match.update!(status: :ended)
      ended = DetailSerializer.call(profile: @target, viewer: @viewer)
      assert_not ended.fetch(:options).key?("physical_affection")
    end

    test "DateZA detail exposes enabled rich scalars and omits disabled historical scalars" do
      brand = Brand.create!(slug: "dateza", name: "DateZA")
      DatezaProfileCatalog.install!(brand:)
      viewer = build_profile_for(brand:)
      target = build_profile_for(
        brand:, job_title: "Engineer", pronouns: "she/her", body_type: "athletic",
        looking_for_text: "A historical value", languages_spoken: [ "English" ]
      )

      payload = DetailSerializer.call(profile: target, viewer:)

      assert_equal "Engineer", payload.fetch(:job_title)
      assert_equal "A historical value", payload.fetch(:looking_for_text)
      %i[pronouns body_type languages_spoken].each do |field|
        assert_not payload.key?(field), "expected disabled #{field} to be omitted"
      end
      assert payload.key?(:prompts)
      assert payload.key?(:interests)
    end

    private

    def build_profile(**attributes)
      build_profile_for(brand: @brand, **attributes)
    end

    def build_profile_for(brand:, **attributes)
      user = User.create!
      membership = BrandMembership.create!(brand:, user:)
      Profile.create!(
        brand:, user:, brand_membership: membership,
        birthdate: 28.years.ago.to_date, status: :active, visibility: :visible, **attributes
      )
    end
  end
end
