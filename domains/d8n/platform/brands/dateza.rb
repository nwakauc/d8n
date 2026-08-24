module D8n
  module Platform
    module Brands
      module Dateza
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
          discovery.surface.browse
          discovery.exposure
          discovery.cursor
          verify.contact.email
          verify.contact.phone
          match.eligibility
          match.compatibility
          match.interaction.like
          match.interaction.pass
          match.relationship.create
          match.relationship.list
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
          notify.event
          notify.inbox
          notify.email
          notify.sms
          notify.push
        ].freeze

        SURFACES = [
          DiscoverySurface.new(
            key: "discovery.find",
            delivery_type: :browse,
            strategy: Matching::Strategies::DatezaV1,
            policy: Matching::Find::Policies::Dateza,
            allocation: {
              type: :daily_exposure,
              limit: Matching::Find::Policies::Dateza::DAILY_LIMIT,
              time_zone: Matching::Find::Policies::Dateza::TIME_ZONE
            }.freeze,
            error_code: :find_not_configured
          )
        ].freeze

        def self.contract(brand:)
          BrandContract.new(
            brand:,
            capabilities: CAPABILITIES,
            profile: BrandContract::ProfileConfiguration.new(catalog: Profiles::DatezaProfileCatalog),
            discovery_surfaces: SURFACES,
            interaction: BrandContract::InteractionConfiguration.new(
              eligibility_strategy: Matching::Find::Policies::Dateza,
              compatibility_strategy: Matching::Strategies::DatezaV1,
              verification_requirement: :verified_login_identifier
            ),
            media: BrandContract::MediaConfiguration.new(
              photo_policy: Media::PhotoPolicy,
              initial_visibility: :moderate_first
            ),
            notifications: BrandContract::NotificationConfiguration.new(
              event_types: %w[membership_registered].freeze
            ),
            error_codes: {
              "discovery.surface.feed" => :matching_not_configured,
              "discovery.find" => :find_not_configured,
              "match.hook" => :hook_not_configured,
              "match.hook_tonight" => :hook_tonight_not_configured
            }
          )
        end
      end
    end
  end
end
