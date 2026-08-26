require "set"

module D8n
  module Platform
    class BrandContract
      ProfileConfiguration = Data.define(:catalog, :detail_decorators) do
        def initialize(catalog:, detail_decorators: [])
          super(catalog:, detail_decorators: Array(detail_decorators).freeze)
        end
      end
      InteractionConfiguration = Data.define(:eligibility_policy, :compatibility_strategy, :verification_requirement)
      MediaConfiguration = Data.define(:photo_policy, :initial_visibility, :max_profile_photos)
      # D8N Opener: a brand's one-shot-opener-then-reply-unlocks-chat policy
      # (implemented by Hooks::SendHook et al. — see Hook/ProfileOpener). Nil for
      # a brand that doesn't enable match.hook/match.opener at all.
      # `catalog_required` selects freeform (HookUs) vs. curated-catalog-only
      # (DateZA) sends; `daily_limit`/`expires_in` are the sender's per-brand
      # anti-spam allowance and the pending window before an unanswered opener
      # lapses.
      OpenerConfiguration = Data.define(:catalog_required, :daily_limit, :expires_in)
      NotificationPlan = Data.define(:notification_type, :email_template)

      class NotificationConfiguration
        attr_reader :event_plans

        def initialize(event_plans: {})
          @event_plans = event_plans.each_with_object({}) do |(event_type, plan), result|
            raise ArgumentError, "notification plan is required" unless plan.is_a?(NotificationPlan)

            result[event_type.to_s] = plan
          end.freeze
          freeze
        end

        def event_types
          event_plans.keys
        end

        def notification_types
          event_plans.values.map(&:notification_type).uniq.freeze
        end

        def plan_for(event_type)
          event_plans[event_type.to_s]
        end
      end

      attr_reader :slug, :auth_methods, :capabilities, :profile, :discovery_surfaces,
        :default_discovery_surface_key,
        :interaction, :media, :opener, :notifications, :error_codes, :enabled_identity_fields,
        :enabled_profile_fields, :enabled_preference_fields, :place_country_codes

      def initialize(
        brand:,
        capabilities:,
        profile:,
        discovery_surfaces: [],
        default_discovery_surface: nil,
        interaction:,
        media:,
        opener: nil,
        notifications:,
        error_codes: {},
        place_country_codes: []
      )
        raise ArgumentError, "brand is required" unless brand.is_a?(Brand)

        @slug = brand.slug.to_s
        raise ArgumentError, "brand slug is required" if slug.blank?

        @auth_methods = Identity::AuthPolicy.available_methods(brand:).freeze
        snapshot_profile_fields(brand)
        @capabilities = Set.new(
          Array(capabilities).map { |key| CapabilityKey.new(key, reserved_segments: [ @slug ]) }
        ).freeze
        @profile = profile
        @discovery_surfaces = index_surfaces(discovery_surfaces)
        @default_discovery_surface_key = default_discovery_surface&.to_s&.freeze
        @interaction = interaction
        @media = media
        @opener = opener
        @notifications = notifications
        @error_codes = error_codes.transform_keys(&:to_s).transform_values(&:to_sym).freeze
        @place_country_codes = Array(place_country_codes).map { |code| code.to_s.upcase }.freeze

        validate!
        freeze
      end

      def capability_enabled?(key)
        capabilities.include?(CapabilityKey.new(key, reserved_segments: [ slug ]))
      end

      def surface(key)
        discovery_surfaces[CapabilityKey.new(key, reserved_segments: [ slug ]).to_s]
      end

      def surface_enabled?(key)
        surface(key).present?
      end

      def error_code_for(key)
        error_codes.fetch(key.to_s, :capability_not_configured)
      end

      private

      def index_surfaces(surfaces)
        Array(surfaces).each_with_object({}) do |surface, index|
          raise ArgumentError, "discovery surface is required" unless surface.is_a?(DiscoverySurface)
          raise ArgumentError, "duplicate discovery surface" if index.key?(surface.key.to_s)

          index[surface.key.to_s] = surface
        end.freeze
      end

      def snapshot_profile_fields(brand)
        requirements = brand.profile_completion_requirements
        @enabled_identity_fields = requirements.fetch("enabled_identity_fields", []).dup.freeze
        @enabled_profile_fields = requirements.fetch(
          "enabled_profile_fields", Profiles::Configuration::PROFILE_FIELD_LABELS.keys
        ).dup.freeze
        @enabled_preference_fields = requirements.fetch(
          "enabled_preference_fields", Profiles::Configuration::PREFERENCE_FIELD_LABELS.keys
        ).dup.freeze
      end

      def validate!
        raise ArgumentError, "profile configuration is required" unless profile.is_a?(ProfileConfiguration)
        raise ArgumentError, "profile catalogue must support install!" unless profile.catalog.respond_to?(:install!)
        raise ArgumentError, "interaction configuration is required" unless interaction.is_a?(InteractionConfiguration)
        unless interaction.eligibility_policy.is_a?(Matching::EligibilityPolicy)
          raise ArgumentError, "interaction eligibility policy is required"
        end
        raise ArgumentError, "media configuration is required" unless media.is_a?(MediaConfiguration)
        unless media.photo_policy.respond_to?(:initial_state) && media.photo_policy.respond_to?(:max_count) &&
            media.max_profile_photos.is_a?(Integer) && media.max_profile_photos.positive?
          raise ArgumentError, "valid media photo policy and maximum are required"
        end
        unless notifications.is_a?(NotificationConfiguration)
          raise ArgumentError, "notification configuration is required"
        end
        if opener && !(opener.is_a?(OpenerConfiguration) && opener.daily_limit.to_i.positive? && opener.expires_in.present?)
          raise ArgumentError, "valid opener configuration is required"
        end
        if (capability_enabled?("match.hook") || capability_enabled?("match.opener")) && opener.nil?
          raise ArgumentError, "opener configuration is required when match.hook or match.opener is enabled"
        end

        capabilities.each do |key|
          definition = Catalog.fetch(key)
          raise ArgumentError, "planned capability cannot be enabled" if definition.planned?

          missing_dependency = definition.dependencies.find { |dependency| !capability_enabled?(dependency) }
          if missing_dependency
            raise ArgumentError, "enabled capability dependency is missing: #{missing_dependency}"
          end
        end

        discovery_surfaces.each_value do |surface|
          unless capability_enabled?(surface.delivery_capability_key)
            raise ArgumentError, "surface delivery capability is not enabled"
          end
        end

        if default_discovery_surface_key.present? && !surface_enabled?(default_discovery_surface_key)
          raise ArgumentError, "default discovery surface is not configured"
        end

        if place_country_codes.any? && !capability_enabled?("profile.location.place_selection")
          raise ArgumentError, "place country codes require the place_selection capability"
        end
      end
    end
  end
end
