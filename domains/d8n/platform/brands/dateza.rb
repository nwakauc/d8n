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
          profile.location.place_selection
          profile.photos
          profile.completion
          profile.publication
          profile.visibility
          discovery.surface.browse
          discovery.surface.daily_batch
          discovery.exposure
          discovery.cursor
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
          match.opener
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

        # DateZA models ProfileLocation as a chosen dating location/area, not a
        # live presence signal: once supplied it stays valid for matching until
        # the member explicitly replaces or removes it. HookUs keeps the 24h
        # freshness default (domains/d8n/platform/brands/hookus.rb) unchanged.
        ELIGIBILITY_POLICY = Matching::EligibilityPolicy::PERSISTENT_LOCATION

        CURATED_DAILY_ALLOCATION = StableDailyAllocationPolicy.new(
          key: "stable_daily_v1",
          daily_limit: 10,
          time_zone: "Africa/Johannesburg"
        )

        # D8N Opener viewer-state (available/pending/hooked/unavailable), under
        # the `opener_state` key — same engine and rules as HookUs's 🔥 Hook
        # (Hooks::ViewerStates), just labeled for DateZA's product naming.
        PROFILE_DECORATORS = [ Hooks::OpenerStateDecorator ].freeze

        SURFACES = [
          DiscoverySurface.new(
            key: "discovery.find",
            delivery_type: :browse,
            strategy: Matching::Strategies::DatezaV1,
            policy: Matching::Find::Policies::Dateza,
            eligibility_policy: ELIGIBILITY_POLICY,
            decorators: PROFILE_DECORATORS,
            error_code: :find_not_configured
          ),
          DiscoverySurface.new(
            key: "discovery.curated_daily",
            delivery_type: :daily_batch,
            strategy: Matching::Strategies::DatezaV1,
            eligibility_policy: ELIGIBILITY_POLICY,
            allocation: CURATED_DAILY_ALLOCATION,
            decorators: PROFILE_DECORATORS,
            error_code: :matching_not_configured
          )
        ].freeze

        def self.contract(brand:)
          BrandContract.new(
            brand:,
            capabilities: CAPABILITIES,
            profile: BrandContract::ProfileConfiguration.new(
              catalog: Profiles::DatezaProfileCatalog,
              detail_decorators: PROFILE_DECORATORS
            ),
            discovery_surfaces: SURFACES,
            place_country_codes: %w[ ZA ],
            phone_country_calling_code: "27",
            default_discovery_surface: "discovery.curated_daily",
            interaction: BrandContract::InteractionConfiguration.new(
              eligibility_policy: ELIGIBILITY_POLICY,
              compatibility_strategy: Matching::Strategies::DatezaV1,
              verification_requirement: :verified_login_identifier
            ),
            media: BrandContract::MediaConfiguration.new(
              photo_policy: Media::PhotoPolicy,
              # DateZA requires moderation before a photo is publicly visible
              # (T6): pending photos are hidden from everyone but the owner
              # until an admin approves them. See domains/media/photo_policy.rb.
              initial_visibility: :moderate_first,
              max_profile_photos: 6
            ),
            # DateZA's browse-first/verify-before-interacting model requires the
            # sender to pick from a curated catalog rather than write freeform
            # text to a stranger (see ProfileOpener). Allowance/expiry reuse the
            # same numbers as HookUs's freeform Hook today.
            opener: BrandContract::OpenerConfiguration.new(
              catalog_required: true,
              daily_limit: Hooks::Policy::FREE_DAILY_LIMIT,
              expires_in: Hooks::Policy::EXPIRES_IN
            ),
            notifications: BrandContract::NotificationConfiguration.new(
              event_plans: {
                "membership_registered" => BrandContract::NotificationPlan.new(
                  notification_type: "dateza.welcome",
                  email_template: :welcome
                ),
                "like_received" => BrandContract::NotificationPlan.new(
                  notification_type: "dateza.like_received",
                  email_template: :product
                ),
                "match_created" => BrandContract::NotificationPlan.new(
                  notification_type: "dateza.match_created",
                  email_template: :product
                ),
                "opener_received" => BrandContract::NotificationPlan.new(
                  notification_type: "dateza.opener_received",
                  email_template: :product
                ),
                "message_received" => BrandContract::NotificationPlan.new(
                  notification_type: "dateza.message_received",
                  email_template: :product
                )
              }
            ),
            error_codes: {
              "discovery.surface.feed" => :matching_not_configured,
              "discovery.find" => :find_not_configured,
              "match.hook" => :hook_not_configured,
              "match.hook_tonight" => :hook_tonight_not_configured,
              "match.opener" => :opener_not_configured
            }
          )
        end
      end
    end
  end
end
