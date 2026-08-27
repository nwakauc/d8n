require "test_helper"

module D8n
  module Platform
    class BrandRegistryTest < ActiveSupport::TestCase
      test "resolves the HookUs capability composition" do
        brand = Brand.new(
          slug: "hookus", name: "HookUs",
          auth_methods: %w[phone_password email_password],
          profile_requirements: Profiles::HookusProfileCatalog::REQUIREMENTS
        )
        contract = BrandRegistry.fetch(brand:)

        assert_equal "hookus", contract.slug
        assert_equal %w[phone_password email_password], contract.auth_methods
        assert_equal Profiles::HookusProfileCatalog, contract.profile.catalog
        assert_equal "27", contract.phone_country_calling_code
        assert contract.capability_enabled?("id.session.browser_persistence")
        assert_equal Profiles::Configuration::PROFILE_FIELD_LABELS.keys, contract.enabled_profile_fields
        assert contract.capability_enabled?("discovery.surface.feed")
        assert contract.capability_enabled?("match.hook")
        assert contract.capability_enabled?("match.hook_tonight")
        assert contract.surface_enabled?("discovery.for_you")
        assert contract.surface_enabled?("discovery.new_here")
        assert contract.surface_enabled?("discovery.hook_tonight")
        assert_equal Matching::Strategies::Hookus, contract.surface("discovery.for_you").strategy
        assert_equal %i[vibe online], contract.surface("discovery.for_you").facets.pluck(:parameter)
        assert_equal [ Hooks::DiscoveryExclusion ], contract.surface("discovery.for_you").exclusions
        assert_equal [ Hooks::DiscoveryExclusion ], contract.surface("discovery.new_here").exclusions
        assert_equal [ Hooks::DiscoveryExclusion ], contract.surface("discovery.hook_tonight").exclusions
        assert_equal Brands::Hookus::PROFILE_DECORATORS, contract.profile.detail_decorators
        assert_equal Brands::Hookus::PROFILE_DECORATORS, contract.surface("discovery.for_you").decorators
        assert_equal :restricted_pool, contract.surface("discovery.hook_tonight").delivery_type
        assert_equal :immediate, contract.media.initial_visibility
      end

      test "resolves DateZA Find as a D8N Discovery browse surface" do
        brand = Brand.new(
          slug: "dateza", name: "DateZA",
          auth_methods: %w[phone_password email_password],
          profile_requirements: Profiles::DatezaProfileCatalog::REQUIREMENTS
        )
        contract = BrandRegistry.fetch(brand:)
        surface = contract.surface("discovery.find")

        assert_equal "dateza", contract.slug
        assert_equal "27", contract.phone_country_calling_code
        assert_equal Profiles::DatezaProfileCatalog, contract.profile.catalog
        assert_equal Profiles::DatezaProfileCatalog::REQUIRED_IDENTITY_FIELDS, contract.enabled_identity_fields
        assert_equal(
          Profiles::DatezaProfileCatalog::REQUIRED_PROFILE_FIELDS +
            Profiles::DatezaProfileCatalog::OPTIONAL_PROFILE_FIELDS,
          contract.enabled_profile_fields
        )
        assert_equal Profiles::DatezaProfileCatalog::REQUIRED_PREFERENCE_FIELDS,
          contract.enabled_preference_fields
        assert contract.capability_enabled?("discovery.surface.browse")
        assert contract.capability_enabled?("id.session.browser_persistence")
        assert_not contract.capability_enabled?("discovery.surface.feed")
        assert contract.capability_enabled?("discovery.surface.daily_batch")
        assert_not contract.capability_enabled?("match.hook")
        assert_not contract.capability_enabled?("match.hook_tonight")
        assert contract.capability_enabled?("match.opener")
        assert contract.opener.catalog_required
        assert surface
        assert_equal :browse, surface.delivery_type
        assert_equal Matching::Find::Policies::Dateza, surface.policy
        assert_equal Matching::Strategies::DatezaV1, surface.strategy
        assert_empty surface.exclusions
        assert_empty surface.facets
        assert_equal [ Hooks::OpenerStateDecorator ], surface.decorators
        assert_equal [ Hooks::OpenerStateDecorator ], contract.profile.detail_decorators
        assert_nil surface.allocation
        assert_equal 10, surface.policy::DAILY_LIMIT
        assert_equal "Africa/Johannesburg", surface.policy::TIME_ZONE
        curated = contract.surface("discovery.curated_daily")
        assert curated
        assert_equal :daily_batch, curated.delivery_type
        assert_equal Matching::Strategies::DatezaV1, curated.strategy
        assert_equal 10, curated.allocation.daily_limit
        assert_equal "Africa/Johannesburg", curated.allocation.time_zone
        assert_equal "discovery.curated_daily", contract.default_discovery_surface_key
        assert_equal :verified_login_identifier, contract.interaction.verification_requirement
        assert_equal :immediate, contract.media.initial_visibility
        assert_equal %w[membership_registered like_received match_created opener_received message_received].sort,
          contract.notifications.event_types.sort
      end

      test "denies nil Date9ja and unknown brands" do
        [ nil, Brand.new(slug: "date9ja", name: "Date9ja"), Brand.new(slug: "future", name: "Future") ].each do |brand|
          error = assert_raises(BrandRegistry::UnsupportedBrand) { BrandRegistry.fetch(brand:) }
          assert_equal :brand_not_configured, error.code
        end
      end

      test "does not allow a brand contract to enable a planned capability" do
        error = assert_raises(ArgumentError) do
          BrandContract.new(
            brand: future_brand,
            capabilities: %w[pay.plan],
            profile: profile_configuration,
            interaction: interaction_configuration,
            media: media_configuration,
            notifications: notification_configuration
          )
        end

        assert_equal "planned capability cannot be enabled", error.message
      end

      test "does not allow a surface without its delivery capability" do
        surface = DiscoverySurface.new(
          key: "discovery.people",
          delivery_type: :feed,
          eligibility_policy: Matching::EligibilityPolicy.new(location_max_age: 24.hours),
          error_code: :matching_not_configured
        )

        error = assert_raises(ArgumentError) do
          BrandContract.new(
            brand: future_brand,
            capabilities: %w[id.registration],
            profile: profile_configuration,
            discovery_surfaces: [ surface ],
            interaction: interaction_configuration,
            media: media_configuration,
            notifications: notification_configuration
          )
        end

        assert_equal "surface delivery capability is not enabled", error.message
      end

      test "does not allow an enabled capability without its declared dependency" do
        error = assert_raises(ArgumentError) do
          BrandContract.new(
            brand: future_brand,
            capabilities: %w[chat.message.text],
            profile: profile_configuration,
            interaction: interaction_configuration,
            media: media_configuration,
            notifications: notification_configuration
          )
        end

        assert_equal "enabled capability dependency is missing: chat.conversation", error.message
      end

      test "capability access fails closed with stable configured errors" do
        dateza = BrandRegistry.fetch(brand: dateza_brand)

        error = assert_raises(CapabilityAccess::NotConfigured) do
          CapabilityAccess.authorize!(contract: dateza, capability: "discovery.surface.feed")
        end
        assert_equal :matching_not_configured, error.code

        hook_error = assert_raises(CapabilityAccess::NotConfigured) do
          CapabilityAccess.authorize!(contract: dateza, capability: "match.hook")
        end
        assert_equal :hook_not_configured, hook_error.code

        surface = CapabilityAccess.authorize!(
          contract: dateza,
          capability: "discovery.surface.browse",
          surface: "discovery.find"
        )
        assert_equal :browse, surface.delivery_type
      end

      test "capability access requires an already resolved production contract" do
        assert_raises(ArgumentError) do
          CapabilityAccess.authorize!(brand: future_brand, capability: "match.interaction.like")
        end
      end

      test "contracts and nested collections are immutable" do
        hookus = Brand.new(
          slug: "hookus", name: "HookUs",
          auth_methods: %w[phone_password email_password]
        )
        contract = BrandRegistry.fetch(brand: hookus)

        assert_predicate contract, :frozen?
        assert_predicate contract.capabilities, :frozen?
        assert_predicate contract.discovery_surfaces, :frozen?
        assert_predicate contract.surface("discovery.for_you").facets, :frozen?
        assert_raises(FrozenError) { contract.auth_methods << "google" }
      end

      test "reuses the authoritative contract within the current brand request" do
        brand = Brand.new(slug: "hookus", name: "HookUs")

        Current.set(brand:) do
          first = BrandRegistry.fetch(brand:)
          assert_same first, BrandRegistry.fetch(brand:)
          assert_same first, Current.platform_contract
        end
      end

      private

      def future_brand
        Brand.new(slug: "future", name: "Future", auth_methods: %w[email_password])
      end

      def dateza_brand
        Brand.new(
          slug: "dateza", name: "DateZA",
          auth_methods: %w[phone_password email_password],
          profile_requirements: Profiles::DatezaProfileCatalog::REQUIREMENTS
        )
      end

      def profile_configuration
        BrandContract::ProfileConfiguration.new(catalog: Profiles::HookusProfileCatalog)
      end

      def interaction_configuration
        BrandContract::InteractionConfiguration.new(
          eligibility_policy: Matching::EligibilityPolicy.new(location_max_age: 24.hours),
          compatibility_strategy: nil,
          verification_requirement: nil
        )
      end

      def media_configuration
        BrandContract::MediaConfiguration.new(
          photo_policy: Media::PhotoPolicy, initial_visibility: :moderate_first, max_profile_photos: 6
        )
      end

      def notification_configuration
        BrandContract::NotificationConfiguration.new
      end
    end
  end
end
