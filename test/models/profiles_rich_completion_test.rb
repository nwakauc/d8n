require "test_helper"

module Profiles
  class RichCompletionTest < ActiveSupport::TestCase
    setup do
      @brand = Brand.create!(slug: "dateza", name: "DateZA")
      DatezaProfileCatalog.install!(brand: @brand)
      @user = User.create!(first_name: "Thandi", last_name: "Mokoena")
      membership = BrandMembership.create!(brand: @brand, user: @user)
      @profile = Profile.create!(
        brand: @brand, user: @user, brand_membership: membership,
        display_name: "Thandi", birthdate: 30.years.ago.to_date, gender: "woman",
        country_code: "ZA", city: "Cape Town", bio: "A real bio.",
        smoking: "never", drinking: "occasionally"
      )
      OptionSelections.replace!(profile: @profile, selections: {
        relationship_intent: [ "long_term_relationship" ],
        has_children: [ "prefer_not_to_say" ],
        wants_children: [ "prefer_not_to_say" ],
        religion_importance: [ "prefer_not_to_say" ],
        social_style: [ "ambivert" ], meeting_pace: [ "few_days" ]
      })
      attach_photo
    end

    test "is deterministic and separate from publication completion" do
      publication = Completion.call(profile: @profile)
      first = RichCompletion.call(profile: @profile)
      second = RichCompletion.call(profile: @profile)

      assert_not publication.complete? # preferences/location are intentionally absent
      assert_equal 39, first.percent
      assert_equal first, second
      assert_equal "starter", first.level
      assert_includes first.missing, "more_photos"
      assert_includes first.missing, "interests"
      assert_includes first.missing, "prompt"
    end

    test "adding optional enrichment increases the score and can reach 100 without sensitive fields" do
      before = RichCompletion.call(profile: @profile)
      2.times { |position| attach_photo(position: position + 1) }
      @profile.update!(
        looking_for_text: "A kind, intentional partner.", job_title: "Designer",
        languages: [ { "code" => "en", "proficiency" => "fluent", "primary" => true } ]
      )
      OptionSelections.replace!(profile: @profile, selections: {
        interests: %w[ hiking live_music travel ], diet: [ "anything" ],
        communication_style: [ "mixed" ]
      })
      PromptAnswers.replace!(
        profile: @profile, answers: [ { key: "green_flag", answer: "I communicate clearly." } ]
      )

      after = RichCompletion.call(profile: @profile)

      assert_operator after.percent, :>, before.percent
      assert_equal 100, after.percent
      assert_equal "standout", after.level
      assert_empty after.missing
      assert_nil @profile.company_name
      assert_not @profile.profile_option_selections.kept.joins(:profile_option_group)
        .where(profile_option_groups: { key: "religion" }).exists?
    end

    test "brands without a richness composition do not inherit DateZA scoring" do
      hookus = Brand.create!(slug: "hookus", name: "HookUs")
      HookusProfileCatalog.install!(brand: hookus)
      user = User.create!
      membership = BrandMembership.create!(brand: hookus, user: user)
      profile = Profile.create!(brand: hookus, user: user, brand_membership: membership)

      assert_nil RichCompletion.call(profile:)
    end

    private

    def attach_photo(position: 0)
      photo = ProfilePhoto.new(profile: @profile, user: @user, brand: @brand, position:)
      photo.image.attach(
        io: Rails.root.join("test/fixtures/files/profile_photo.png").open,
        filename: "profile_photo.png", content_type: "image/png"
      )
      photo.save!
    end
  end
end
