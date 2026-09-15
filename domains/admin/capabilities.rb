module Admin
  # The single authorization vocabulary for every current and planned HQ/admin
  # surface. Role names are data; capability semantics live here and nowhere in
  # controllers. Capabilities for later phases grant no endpoint by themselves.
  module Capabilities
    MEMBER_SENSITIVE_READ = "hq.member.sensitive_read"
    MEMBER_SECURITY_READ = "hq.member.security_read"
    DISCOVERY_DIAGNOSTICS_READ = "hq.discovery_diagnostics.read"
    TRUST_SAFETY_READ = "hq.trust_safety.read"
    REPORTS_READ = "admin.reports.read"
    REPORTS_MODERATE = "admin.reports.moderate"
    ENFORCEMENTS_MANAGE = "admin.enforcements.manage"
    ENFORCEMENTS_READ = "admin.enforcements.read"
    ENFORCEMENTS_CREATE = "admin.enforcements.create"
    ENFORCEMENTS_REINSTATE = "admin.enforcements.reinstate"
    ENFORCEMENTS_OVERRIDE = "admin.enforcements.override"
    PROFILE_PHOTOS_MODERATE = "admin.profile_photos.moderate"
    REALME_VERIFICATIONS_MODERATE = "admin.realme_verifications.moderate"
    TRUST_ADJUSTMENTS_MANAGE = "admin.trust_adjustments.manage"
    TRUST_ADJUSTMENTS_REVERSE = "admin.trust_adjustments.reverse"
    DISCOVERY_RESTRICTIONS_MANAGE = "admin.discovery_restrictions.manage"
    IDENTITY_CORRECTION_MANAGE = "admin.identity_correction.manage"
    COMMUNITY_READ = "admin.community.read"
    COMMUNITY_MODERATE = "admin.community.moderate"
    OPERATORS_READ = "admin.operators.read"
    OPERATORS_MANAGE = "admin.operators.manage"
    BRAND_OPERATIONS = "admin.brand_operations.manage"
    SYSTEM_READ = "hq.system.read"
    ANALYTICS_READ = "hq.analytics.read"
    SECURITY_ALERTS_READ = "hq.security_alerts.read"

    CURRENT_OPERATIONAL = [
      MEMBER_SENSITIVE_READ,
      MEMBER_SECURITY_READ,
      DISCOVERY_DIAGNOSTICS_READ,
      TRUST_SAFETY_READ,
      REPORTS_READ,
      REPORTS_MODERATE,
      ENFORCEMENTS_MANAGE,
      PROFILE_PHOTOS_MODERATE,
      REALME_VERIFICATIONS_MODERATE,
      COMMUNITY_READ,
      COMMUNITY_MODERATE,
      # Lighter than suspension/ban (no session revocation, no account lock) —
      # routine, frequent moderation, so it travels with CURRENT_OPERATIONAL
      # the same way ENFORCEMENTS_MANAGE does.
      DISCOVERY_RESTRICTIONS_MANAGE
    ].freeze

    ALL = (CURRENT_OPERATIONAL + [
      ENFORCEMENTS_READ,
      ENFORCEMENTS_CREATE,
      ENFORCEMENTS_REINSTATE,
      ENFORCEMENTS_OVERRIDE,
      # Deliberately not in CURRENT_OPERATIONAL/"moderator" — docking trust
      # points, reversing a deduction, and correcting a member's identity
      # fields are each a step above ordinary content moderation, so they
      # stay opt-in per role (trust_safety below, plus founder/super_admin
      # here).
      TRUST_ADJUSTMENTS_MANAGE,
      TRUST_ADJUSTMENTS_REVERSE,
      IDENTITY_CORRECTION_MANAGE,
      OPERATORS_READ,
      OPERATORS_MANAGE,
      BRAND_OPERATIONS,
      SYSTEM_READ,
      ANALYTICS_READ,
      SECURITY_ALERTS_READ
    ]).freeze

    ROLE_CAPABILITIES = {
      "founder" => ALL,
      "super_admin" => ALL,
      "operations" => [
        MEMBER_SENSITIVE_READ, MEMBER_SECURITY_READ,
        DISCOVERY_DIAGNOSTICS_READ, TRUST_SAFETY_READ,
        REPORTS_READ, ENFORCEMENTS_READ, ENFORCEMENTS_CREATE,
        ANALYTICS_READ, OPERATORS_READ, BRAND_OPERATIONS,
        SECURITY_ALERTS_READ
      ],
      "trust_safety" => [
        MEMBER_SENSITIVE_READ, MEMBER_SECURITY_READ,
        TRUST_SAFETY_READ, REPORTS_READ, REPORTS_MODERATE,
        ENFORCEMENTS_MANAGE, ENFORCEMENTS_READ, ENFORCEMENTS_CREATE,
        PROFILE_PHOTOS_MODERATE, REALME_VERIFICATIONS_MODERATE,
        TRUST_ADJUSTMENTS_MANAGE, TRUST_ADJUSTMENTS_REVERSE,
        DISCOVERY_RESTRICTIONS_MANAGE, IDENTITY_CORRECTION_MANAGE,
        SECURITY_ALERTS_READ
      ],
      "support" => [ MEMBER_SENSITIVE_READ, DISCOVERY_DIAGNOSTICS_READ ],
      "engineering" => [ DISCOVERY_DIAGNOSTICS_READ, SYSTEM_READ ],
      "marketing" => [ ANALYTICS_READ ],
      "analyst" => [ ANALYTICS_READ ],
      # Compatibility for assignments created under ADR 0013. It preserves
      # exactly the current moderation/HQ surface but cannot manage operators.
      "moderator" => (CURRENT_OPERATIONAL + [ ENFORCEMENTS_READ, ENFORCEMENTS_CREATE, ENFORCEMENTS_REINSTATE ])
    }.transform_values { |values| values.map(&:freeze).uniq.sort.freeze }.freeze

    ROLE_NAMES = ROLE_CAPABILITIES.keys.freeze
    PRIVILEGED_ROLE_NAMES = %w[founder super_admin].freeze

    module_function

    def for_role(role_name)
      ROLE_CAPABILITIES.fetch(role_name.to_s, EMPTY)
    end

    def known_role?(role_name)
      ROLE_CAPABILITIES.key?(role_name.to_s)
    end

    EMPTY = [].freeze
  end
end
