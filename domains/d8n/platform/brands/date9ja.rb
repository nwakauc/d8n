module D8n
  module Platform
    module Brands
      # Date9ja platform brand contract — BRAND FOUNDATION slice.
      #
      # This enables only the shared D8N capabilities that are un-blocked for
      # Date9ja today: identity/session/account, the non-sensitive profile
      # capability surface, contact verification, private profile media, brand
      # notifications, and the core safety actions (block/report).
      #
      # Deliberately NOT enabled yet (each waits on its own remediation/decision
      # slice — see docs/migrations/date9ja-to-d8n/MASTER-PLAN.md and
      # PARITY-BUILD-PLAN.md):
      #   * discovery.* / match.* / chat.* — need Date9ja discovery surface,
      #     ranking and location semantics plus the brand-scoped profile write
      #     remediation.
      #   * match.opener — needs the Date9ja interaction product decision.
      #   * verify.identity.* / trust.reputation — verification and Trust XP
      #     architecture decisions are open.
      #
      # Fields blocked by DECISIONS.md are left conservative, not invented:
      #   * photo publication policy is unresolved -> moderate-first (a new photo
      #     stays hidden until moderation), matching Media::PhotoPolicy's default.
      #   * verification prerequisites are unresolved -> no interaction
      #     verification requirement.
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
          profile.location.place_selection
          profile.photos
          profile.completion
          profile.publication
          profile.visibility
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
          notify.event
          notify.inbox
          notify.email
          notify.sms
          notify.push
        ].freeze

        # Date9ja models a member's location as a chosen city/area that stays
        # valid for matching until they change it, not a live freshness signal —
        # the same product shape as DateZA, so it reuses the shared persistent
        # location eligibility policy. This is configuration, not Date9ja
        # discovery logic (which is a separate remediation slice).
        ELIGIBILITY_POLICY = Matching::EligibilityPolicy::PERSISTENT_LOCATION

        def self.contract(brand:)
          BrandContract.new(
            brand:,
            capabilities: CAPABILITIES,
            profile: BrandContract::ProfileConfiguration.new(
              catalog: Profiles::Date9jaProfileCatalog
            ),
            place_country_codes: %w[ NG ],
            phone_country_calling_code: "234",
            interaction: BrandContract::InteractionConfiguration.new(
              eligibility_policy: ELIGIBILITY_POLICY,
              compatibility_strategy: nil,
              verification_requirement: nil
            ),
            media: BrandContract::MediaConfiguration.new(
              photo_policy: Media::PhotoPolicy,
              # Blocked by the "Approved photo publication" decision in
              # DECISIONS.md — stay moderate-first until product decides.
              initial_visibility: :moderate_first,
              max_profile_photos: 6
            ),
            notifications: BrandContract::NotificationConfiguration.new(
              event_plans: {
                "membership_registered" => BrandContract::NotificationPlan.new(
                  notification_type: "date9ja.welcome",
                  email_template: :welcome
                )
              }
            )
          )
        end
      end
    end
  end
end
