require "set"

module D8n
  module Platform
    class BrandContract
      ProfileConfiguration = Data.define(:catalog)
      InteractionConfiguration = Data.define(:eligibility_strategy, :compatibility_strategy, :verification_requirement)
      MediaConfiguration = Data.define(:photo_policy, :initial_visibility)
      NotificationConfiguration = Data.define(:event_types)

      attr_reader :slug, :auth_methods, :capabilities, :profile, :discovery_surfaces,
        :interaction, :media, :notifications, :error_codes, :enabled_identity_fields,
        :enabled_profile_fields, :enabled_preference_fields

      def initialize(
        brand:,
        capabilities:,
        profile:,
        discovery_surfaces: [],
        interaction:,
        media:,
        notifications:,
        error_codes: {}
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
        @interaction = interaction
        @media = media
        @notifications = normalize_notifications(notifications)
        @error_codes = error_codes.transform_keys(&:to_s).transform_values(&:to_sym).freeze

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

      def normalize_notifications(configuration)
        NotificationConfiguration.new(event_types: Array(configuration.event_types).map(&:to_s).uniq.freeze)
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
        raise ArgumentError, "media configuration is required" unless media.is_a?(MediaConfiguration)

        capabilities.each do |key|
          definition = Catalog.fetch(key)
          raise ArgumentError, "planned capability cannot be enabled" if definition.planned?
        end

        discovery_surfaces.each_value do |surface|
          unless capability_enabled?(surface.delivery_capability_key)
            raise ArgumentError, "surface delivery capability is not enabled"
          end
        end
      end
    end
  end
end
