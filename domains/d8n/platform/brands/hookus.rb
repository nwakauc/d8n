module D8n
  module Platform
    module Brands
      module Hookus
        CAPABILITIES = %w[
          id.registration
          id.authentication.email_password
          id.authentication.phone_password
          id.session.create
          id.session.destroy
          id.session.current
          id.session.browser_persistence
          id.password_recovery
          id.password_reset
          id.contact_change.email
          id.membership
          id.account.close_brand_membership
          id.account.password_change
          id.account.deactivate
          profile.onboarding
          profile.scalar_fields
          profile.options
          profile.preferences
          profile.prompts
          profile.interests
          profile.languages
          profile.location
          profile.photos
          profile.completion
          profile.publication
          profile.visibility
          discovery.surface.feed
          discovery.surface.restricted_pool
          discovery.facet.activity
          discovery.facet.option_group
          discovery.cursor
          discovery.decoration
          verify.contact.email
          verify.contact.phone
          match.eligibility
          match.compatibility
          match.ranking
          match.interaction.like
          match.interaction.pass
          match.relationship.create
          match.relationship.list
          match.relationship.unmatch
          match.hook
          match.hook_tonight
          chat.conversation
          chat.message.text
          chat.message.media
          trust.block
          trust.report
          trust.report_evidence
          media.profile_photo.upload
          media.profile_photo.attach
          media.profile_photo.process
          media.profile_photo.deliver
          media.profile_photo.delete
          media.profile_photo.moderation
          notify.email
          notify.sms
        ].freeze

        FACETS = [
          { type: :option_group, parameter: :vibe, option_group: "vibes" },
          { type: :activity, parameter: :online }
        ].freeze

        PROFILE_DECORATORS = [ Hooks::ProfileStateDecorator, HookTonight::ProfileStateDecorator ].freeze

        ELIGIBILITY_POLICY = Matching::EligibilityPolicy::DEFAULT

        SURFACES = [
          DiscoverySurface.new(
            key: "discovery.for_you",
            delivery_type: :feed,
            strategy: Matching::Strategies::Hookus,
            eligibility_policy: ELIGIBILITY_POLICY,
            facets: FACETS,
            exclusions: [ Hooks::DiscoveryExclusion ],
            decorators: PROFILE_DECORATORS,
            error_code: :matching_not_configured
          ),
          DiscoverySurface.new(
            key: "discovery.new_here",
            delivery_type: :feed,
            strategy: Matching::Strategies::HookusNewHere,
            eligibility_policy: ELIGIBILITY_POLICY,
            facets: FACETS,
            exclusions: [ Hooks::DiscoveryExclusion ],
            decorators: PROFILE_DECORATORS,
            error_code: :matching_not_configured
          ),
          DiscoverySurface.new(
            key: "discovery.hook_tonight",
            delivery_type: :restricted_pool,
            strategy: Matching::Strategies::Hookus,
            policy: HookTonight::Policy,
            eligibility_policy: ELIGIBILITY_POLICY,
            facets: FACETS,
            exclusions: [ Hooks::DiscoveryExclusion ],
            decorators: PROFILE_DECORATORS,
            error_code: :hook_tonight_not_configured
          )
        ].freeze

        def self.contract(brand:)
          BrandContract.new(
            brand:,
            capabilities: CAPABILITIES,
            profile: BrandContract::ProfileConfiguration.new(
              catalog: Profiles::HookusProfileCatalog,
              detail_decorators: PROFILE_DECORATORS
            ),
            discovery_surfaces: SURFACES,
            phone_country_calling_code: "27",
            default_discovery_surface: "discovery.for_you",
            interaction: BrandContract::InteractionConfiguration.new(
              eligibility_policy: ELIGIBILITY_POLICY,
              compatibility_strategy: nil,
              verification_requirement: nil
            ),
            media: BrandContract::MediaConfiguration.new(
              photo_policy: Media::PhotoPolicy,
              initial_visibility: :immediate,
              max_profile_photos: 6
            ),
            opener: BrandContract::OpenerConfiguration.new(
              catalog_required: false,
              daily_limit: Hooks::Policy::FREE_DAILY_LIMIT,
              expires_in: Hooks::Policy::EXPIRES_IN
            ),
            notifications: BrandContract::NotificationConfiguration.new,
            error_codes: {
              "discovery.surface.feed" => :matching_not_configured,
              "match.hook" => :hook_not_configured,
              "match.hook_tonight" => :hook_tonight_not_configured
            }
          )
        end
      end
    end
  end
end
