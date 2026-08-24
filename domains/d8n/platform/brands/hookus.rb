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
          id.password_recovery
          id.password_reset
          id.contact_change.email
          id.membership
          id.account.close_brand_membership
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
          match.hook
          match.hook_tonight
          chat.conversation
          chat.message.text
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
          { type: :activity, parameter: :online },
          { type: :option_group, parameter: :vibe, option_group: "vibes" }
        ].freeze

        SURFACES = [
          DiscoverySurface.new(
            key: "discovery.for_you",
            delivery_type: :feed,
            strategy: Matching::Strategies::Hookus,
            facets: FACETS,
            exclusions: [ Matching::ExclusionsScope ],
            decorators: [ Hooks::ViewerStates ],
            error_code: :matching_not_configured
          ),
          DiscoverySurface.new(
            key: "discovery.new_here",
            delivery_type: :feed,
            strategy: Matching::Strategies::HookusNewHere,
            facets: FACETS,
            exclusions: [ Matching::ExclusionsScope ],
            decorators: [ Hooks::ViewerStates ],
            error_code: :matching_not_configured
          ),
          DiscoverySurface.new(
            key: "discovery.hook_tonight",
            delivery_type: :restricted_pool,
            strategy: Matching::Strategies::Hookus,
            policy: HookTonight::Policy,
            exclusions: [ Matching::ExclusionsScope ],
            decorators: [ Hooks::ViewerStates ],
            error_code: :hook_tonight_not_configured
          )
        ].freeze

        def self.contract(brand:)
          BrandContract.new(
            brand:,
            capabilities: CAPABILITIES,
            profile: BrandContract::ProfileConfiguration.new(catalog: Profiles::HookusProfileCatalog),
            discovery_surfaces: SURFACES,
            interaction: BrandContract::InteractionConfiguration.new(
              eligibility_strategy: Matching::Strategies::Hookus,
              compatibility_strategy: Matching::Strategies::Hookus,
              verification_requirement: nil
            ),
            media: BrandContract::MediaConfiguration.new(
              photo_policy: Media::PhotoPolicy,
              initial_visibility: :immediate
            ),
            notifications: BrandContract::NotificationConfiguration.new(event_types: [].freeze),
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
