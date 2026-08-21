require "test_helper"

module Profiles
  class CapabilityCatalogTest < ActiveSupport::TestCase
    setup { @brand = Brand.create!(slug: "dateza", name: "DateZA") }

    test "a new brand composes generic capabilities without editing the catalogue" do
      # Demonstrates reuse: DateZA enables a DIFFERENT subset than HookUs, using the
      # same generic definitions, with its own labels/visibility/values.
      CapabilityCatalog.enable_option_capability!(
        brand: @brand, key: "relationship_intent", position: 0,
        label: "Looking for", only: %w[ long_term_relationship marriage friendship ]
      )
      CapabilityCatalog.enable_option_capability!(brand: @brand, key: "religion", position: 1, visibility: :public_profile)
      CapabilityCatalog.enable_interests!(brand: @brand, position: 2, categories: %w[ food music ])
      CapabilityCatalog.enable_prompts!(brand: @brand, keys: %w[ perfect_night dealbreaker ])

      intent = @brand.profile_option_groups.kept.find_by!(key: "relationship_intent")
      assert_equal "Looking for", intent.label
      assert_equal %w[ friendship long_term_relationship marriage ], intent.profile_options.kept.pluck(:code).sort
      # Stable codes carry a fixed meaning across brands.
      assert_includes intent.profile_options.kept.pluck(:code), "marriage"

      # DateZA chose to expose religion publicly (explicit), overriding the
      # conservative generic default.
      assert @brand.profile_option_groups.kept.find_by!(key: "religion").visibility_public_profile?

      interests = @brand.profile_option_groups.kept.find_by!(key: "interests")
      assert_equal %w[ food music ].to_set, interests.profile_options.kept.pluck(:category).to_set
      assert_equal 2, @brand.profile_prompts.kept.count
    end

    test "generic sensitive capabilities default to a conservative, non-public visibility" do
      %w[ sexual_orientation religion has_children cannabis ].each do |key|
        assert_equal :owner_only, CapabilityCatalog::OPTION_CAPABILITIES.fetch(key).fetch(:visibility),
          "#{key} must default to owner_only"
      end
      %w[ physical_affection public_affection chemistry_importance ].each do |key|
        assert_equal :matches_only, CapabilityCatalog::OPTION_CAPABILITIES.fetch(key).fetch(:visibility)
      end
    end

    test "install is idempotent and raises on unknown capabilities" do
      CapabilityCatalog.enable_option_capability!(brand: @brand, key: "diet", position: 0)
      assert_no_difference [ -> { ProfileOptionGroup.count }, -> { ProfileOption.count } ] do
        CapabilityCatalog.enable_option_capability!(brand: @brand, key: "diet", position: 0)
      end
      assert_raises(CapabilityCatalog::UnknownCapability) do
        CapabilityCatalog.enable_option_capability!(brand: @brand, key: "not_a_thing", position: 9)
      end
    end
  end
end
