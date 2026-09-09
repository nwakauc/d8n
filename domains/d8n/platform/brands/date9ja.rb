module D8n
  module Platform
    module Brands
      # Date9ja platform brand contract.
      #
      # This enables the shared D8N identity, profile, core dating-loop, media,
      # notification, and safety capabilities that are currently approved for
      # Date9ja.
      #
      # The core dating loop uses only shared D8N discovery, matching and chat.
      # Historical graph migration and opener semantics remain separate slices.
      # Verification and Trust XP remain intentionally unconfigured pending
      # their separate architecture/product decisions.
      #
      # Fields blocked by DECISIONS.md are left conservative, not invented. The
      # legacy Date9ja API exposes pending photos and removes rejected photos;
      # use D8N's immediate visibility state to preserve that behavior until a
      # product decision explicitly changes it.
      # No interaction-verification prerequisite is enabled in this slice.
      module Date9ja
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
          profile.video
          profile.completion
          profile.publication
          profile.visibility
          discovery.surface.browse
          discovery.exposure
          discovery.cursor
          match.eligibility
          match.compatibility
          match.ranking
          match.interaction.like
          match.interaction.pass
          match.relationship.create
          match.relationship.list
          match.relationship.unmatch
          chat.conversation
          chat.message.text
          verify.contact.email
          verify.contact.phone
          trust.block
          trust.report
          trust.report_evidence
          media.profile_photo.upload
          media.profile_photo.attach
          media.profile_photo.process
          media.profile_photo.deliver
          media.profile_photo.delete
          media.profile_photo.moderation
          media.profile_video.upload
          media.profile_video.attach
          media.profile_video.process
          media.profile_video.deliver
          media.profile_video.delete
          media.profile_video.moderation
          notify.event
          notify.inbox
          notify.email
          notify.sms
          notify.push
        ].freeze

        # Date9ja's matching product uses country/city profile fields and does
        # not apply coordinate or distance eligibility. This is configuration,
        # not a Date9ja-specific discovery implementation.
        ELIGIBILITY_POLICY = Matching::EligibilityPolicy::NO_LOCATION

        def self.contract(brand:)
          BrandContract.new(
            brand:,
            capabilities: CAPABILITIES,
            profile: BrandContract::ProfileConfiguration.new(
              catalog: Profiles::Date9jaProfileCatalog
            ),
            # Date9ja stores the selected country/city as profile fields; it
            # does not use the canonical Place/ProfileLocation selector.
            place_country_codes: [],
            phone_country_calling_code: "234",
            interaction: BrandContract::InteractionConfiguration.new(
              eligibility_policy: ELIGIBILITY_POLICY,
              compatibility_strategy: Matching::Strategies::Date9jaContract,
              verification_requirement: nil
            ),
            media: BrandContract::MediaConfiguration.new(
              photo_policy: Media::PhotoPolicy,
              # Preserve Date9ja's current pending-visible/rejected-hidden
              # behavior. This is not a new moderation policy.
              initial_visibility: :immediate,
              max_profile_photos: 6,
              # ADR 0023 — profile introduction video. Legacy Date9ja limits:
              # <= 60s, <= 50MB, pending-visible/rejected-excluded.
              video: BrandContract::VideoConfiguration.new(
                policy: Media::VideoPolicy,
                initial_visibility: :immediate,
                max_duration_seconds: 60,
                max_byte_size: 50.megabytes
              )
            ),
            notifications: BrandContract::NotificationConfiguration.new(
              event_plans: {
                "membership_registered" => BrandContract::NotificationPlan.new(
                  notification_type: "date9ja.welcome",
                  email_template: :welcome
                ),
                "like_received" => BrandContract::NotificationPlan.new(
                  notification_type: "date9ja.like_received",
                  email_template: :product
                ),
                "match_created" => BrandContract::NotificationPlan.new(
                  notification_type: "date9ja.match_created",
                  email_template: :product
                ),
                "message_received" => BrandContract::NotificationPlan.new(
                  notification_type: "date9ja.message_received",
                  email_template: :product
                )
              }
            ),
            discovery_surfaces: [
              DiscoverySurface.new(
                key: "discovery.find",
                delivery_type: :browse,
                strategy: Matching::Strategies::Date9jaContract,
                eligibility_policy: ELIGIBILITY_POLICY,
                error_code: :find_not_configured
              )
            ],
            default_discovery_surface: "discovery.find",
            error_codes: {
              "discovery.find" => :find_not_configured
            }
          )
        end
      end
    end
  end
end
