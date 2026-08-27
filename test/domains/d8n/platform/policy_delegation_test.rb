require "test_helper"

module D8n
  module Platform
    class PolicyDelegationTest < ActiveSupport::TestCase
      setup do
        @hookus = Brand.new(slug: "hookus", name: "HookUs")
        @dateza = Brand.new(slug: "dateza", name: "DateZA")
        @unknown = Brand.new(slug: "unknown", name: "Unknown")
      end

      test "matching discovery modes resolve through configured surfaces" do
        assert_equal Matching::Strategies::Hookus, Matching::StrategyRegistry.fetch(brand: @hookus)
        assert_equal Matching::Strategies::Hookus,
          Matching::StrategyRegistry.fetch(brand: @hookus, mode: "for_you")
        assert_equal Matching::Strategies::HookusNewHere,
          Matching::StrategyRegistry.fetch(brand: @hookus, mode: "new_here")

        assert_raises(Matching::StrategyRegistry::UnsupportedMode) do
          Matching::StrategyRegistry.fetch(brand: @hookus, mode: "unknown")
        end
        assert_equal Matching::Strategies::DatezaV1,
          Matching::StrategyRegistry.fetch(brand: @dateza)
        assert_raises(Matching::StrategyRegistry::UnsupportedBrand) do
          Matching::StrategyRegistry.fetch(brand: @unknown)
        end

        restricted = Matching::StrategyRegistry.fetch_surface(brand: @hookus, mode: "hook_tonight")
        assert_equal :restricted_pool, restricted.delivery_type
        assert_equal D8n::Platform::CapabilityKey.new("discovery.surface.restricted_pool"),
          restricted.delivery_capability_key
      end

      test "matching discovery rejects a configured surface whose strategy is not production ready" do
        strategy = Class.new do
          def self.production_ready? = false
        end
        surface = Struct.new(:strategy, :delivery_type).new(strategy, :feed)

        stub_method(Matching::StrategyRegistry, :surface_for, ->(brand:, mode: nil) { surface }) do
          assert_raises(Matching::StrategyRegistry::UnsupportedBrand) do
            Matching::StrategyRegistry.fetch_surface(brand: @hookus)
          end
        end
      end

      test "matching interaction eligibility and compatibility resolve through the contract" do
        assert_same Brands::Hookus::ELIGIBILITY_POLICY,
          Matching::StrategyRegistry.eligibility_policy_for(brand: @hookus)
        assert_same Brands::Dateza::ELIGIBILITY_POLICY,
          Matching::StrategyRegistry.eligibility_policy_for(brand: @dateza)
        assert_equal Matching::Strategies::DatezaV1,
          Matching::StrategyRegistry.compatibility_for(brand: @dateza)

        assert_raises(Matching::StrategyRegistry::UnsupportedBrand) do
          Matching::StrategyRegistry.compatibility_for(brand: @hookus)
        end
        assert_raises(Matching::StrategyRegistry::UnsupportedBrand) do
          Matching::StrategyRegistry.eligibility_policy_for(brand: @unknown)
        end
      end

      test "Find policy resolution delegates to the DateZA browse surface" do
        assert_equal Matching::Find::Policies::Dateza,
          Matching::Find::PolicyRegistry.fetch(brand: @dateza)

        [ @hookus, @unknown ].each do |brand|
          assert_raises(Matching::Find::PolicyRegistry::UnsupportedBrand) do
            Matching::Find::PolicyRegistry.fetch(brand:)
          end
        end
      end

      test "media policy delegates known brands and preserves conservative unknown default" do
        assert_same Media::PhotoPolicy::IMMEDIATE, Media::PhotoPolicy.initial_state(brand: @hookus)
        assert_same Media::PhotoPolicy::MODERATE_FIRST, Media::PhotoPolicy.initial_state(brand: @dateza)
        assert_same Media::PhotoPolicy::MODERATE_FIRST, Media::PhotoPolicy.initial_state(brand: @unknown)
      end

      test "notification policy and type authorization share the DateZA contract" do
        assert Notifications::Policy.handles?(brand: @dateza, event_type: "membership_registered")
        assert_not Notifications::Policy.handles?(brand: @hookus, event_type: "membership_registered")
        assert_not Notifications::Policy.handles?(brand: @unknown, event_type: "membership_registered")

        assert_empty Notifications::Types.validate_payload(
          notification_type: "dateza.welcome", payload: {}, brand: @dateza
        )
        assert_equal [ "is not supported for this brand" ], Notifications::Types.validate_payload(
          notification_type: "dateza.welcome", payload: {}, brand: @hookus
        )
      end

      test "legacy enablement maps no longer compete with the brand contract" do
        assert_not Matching::StrategyRegistry.const_defined?(:MODES, false)
        assert_not Matching::StrategyRegistry.const_defined?(:INTERACTION_STRATEGIES, false)
        assert_not Matching::StrategyRegistry.const_defined?(:COMPATIBILITY_STRATEGIES, false)
        assert_not Matching::Find::PolicyRegistry.const_defined?(:POLICIES, false)
        assert_not Identity::InteractionAccess.const_defined?(:REQUIREMENTS, false)
        assert_not Media::PhotoPolicy.const_defined?(:BRAND_POLICIES, false)
        assert_not Notifications::Policy.const_defined?(:EVENT_PLANS, false)
      end
    end
  end
end
