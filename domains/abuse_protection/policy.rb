module AbuseProtection
  # Single, tunable source of truth for every generic abuse-protection limit in
  # the D8N platform. These are SECURITY ceilings, not product entitlements:
  # every number is set high enough that ordinary human usage never approaches
  # it, while automated flooding does. Free/Plus allowances, paid discovery
  # limits, and premium media rules are entitlement policy and deliberately live
  # elsewhere (see Hooks::Policy for the product Hook allowance, which this layer
  # never replaces).
  #
  # Each action maps to one or more rules. A rule is a (scope, limit, window)
  # fixed-window counter; an action trips as soon as ANY of its rules is
  # exceeded. Pair a short BURST rule (stops rapid-fire scripting) with a longer
  # SUSTAINED rule (stops slow high-volume abuse). Rules are evaluated
  # burst-first so the tightest window rejects earliest.
  #
  # Scope decides the throttle identity and, with it, brand isolation:
  #   :user — per (brand, authenticated user). Brand is part of the key, so
  #           activity on one brand can never consume another brand's counter.
  #   :ip   — per client IP, PLATFORM-WIDE (brand-independent) on purpose: a
  #           scraper/abuser must not reset an IP ceiling by switching brand host.
  module Policy
    # A single fixed-window limit. `window` is an ActiveSupport::Duration.
    Rule = Data.define(:name, :scope, :limit, :window) do
      # Epoch-aligned bucket boundary for `now`, so all nodes agree on the window
      # without coordination.
      def bucket_start(now)
        seconds = window.to_i
        Time.zone.at((now.to_i / seconds) * seconds)
      end
    end

    def self.rule(name, scope:, limit:, window:)
      Rule.new(name:, scope:, limit:, window:)
    end

    RULES = {
      # Messaging: real conversations can fire several short messages quickly, so
      # the burst ceiling is generous; the sustained ceiling stops scripted spam.
      send_message: [
        rule("burst",     scope: :user, limit: 30,  window: 10.seconds),
        rule("sustained", scope: :user, limit: 600, window: 1.hour)
      ],

      # Likes / Passes: fast swiping is normal, mass automation is not. Abuse
      # ceiling only — NOT a free/premium Like allowance.
      like_profile: [
        rule("burst",     scope: :user, limit: 40,   window: 10.seconds),
        rule("sustained", scope: :user, limit: 1500, window: 1.hour)
      ],
      pass_profile: [
        rule("burst",     scope: :user, limit: 40,   window: 10.seconds),
        rule("sustained", scope: :user, limit: 1500, window: 1.hour)
      ],

      # Reporting: conservative but victim-safe — a user may still report many
      # distinct bad actors. A per-IP ceiling curbs multi-account report brigading
      # from one host. Requests are never silently dropped; a tripped limit is a
      # controlled 429.
      report_profile: [
        rule("burst",     scope: :user, limit: 10,  window: 1.minute),
        rule("sustained", scope: :user, limit: 60,  window: 1.hour),
        rule("ip",        scope: :ip,   limit: 120, window: 1.hour)
      ],

      # Media upload intents are expensive downstream (R2 objects, HEAD/verify,
      # image processing, Solid Queue). Onboarding a full photo set is a handful
      # of intents; the per-IP ceiling curbs storage-abuse from one host.
      media_upload_intent: [
        rule("burst",     scope: :user, limit: 20,  window: 1.minute),
        rule("sustained", scope: :user, limit: 120, window: 1.hour),
        rule("ip",        scope: :ip,   limit: 300, window: 1.hour)
      ],
      # Attaching a verified object also drives verification + processing work.
      media_attach: [
        rule("burst",     scope: :user, limit: 20,  window: 1.minute),
        rule("sustained", scope: :user, limit: 120, window: 1.hour)
      ],

      # One shared bucket for every profile-mutation surface (scalar PATCH, option
      # selections, prompt answers, preferences). Rationale: to a user these are
      # all "editing my profile", so a shared generous ceiling stops write floods
      # without penalising someone filling out a rich profile across sections.
      profile_write: [
        rule("burst",     scope: :user, limit: 60,  window: 10.seconds),
        rule("sustained", scope: :user, limit: 600, window: 1.hour)
      ],

      # Discovery reads: normal load/scroll/paginate/refilter is bursty but
      # bounded; the sustained ceiling stops high-frequency enumeration/scraping.
      # Cursor behaviour, ranking, visibility, and eligibility are untouched.
      discovery: [
        rule("burst",     scope: :user, limit: 40,   window: 10.seconds),
        rule("sustained", scope: :user, limit: 1200, window: 1.hour)
      ],
      # Find has a durable product allowance in Matching::Find. This separate,
      # deliberately high abuse ceiling only curbs replay/scraping traffic; it is
      # never used to decide how many unique profiles a member may explore.
      find_profiles: [
        rule("burst",     scope: :user, limit: 40,   window: 10.seconds),
        rule("sustained", scope: :user, limit: 1200, window: 1.hour)
      ],
      # Hook Tonight's pool is a separate population, so it gets its own bucket
      # rather than starving (or being starved by) ordinary discovery.
      hook_tonight_discovery: [
        rule("burst",     scope: :user, limit: 40,   window: 10.seconds),
        rule("sustained", scope: :user, limit: 1200, window: 1.hour)
      ],

      # Hook Tonight activation/deactivation are idempotent state flips; this only
      # curbs pathological request flooding, not the 6-hour availability semantics.
      hook_tonight_activation: [
        rule("burst",     scope: :user, limit: 20,  window: 1.minute),
        rule("sustained", scope: :user, limit: 120, window: 1.hour)
      ],

      # Location/area search: an interactive, debounced typeahead. The burst
      # ceiling comfortably covers a member typing a whole suburb name; the
      # sustained ceiling curbs scripted enumeration of the geography catalog.
      location_search: [
        rule("burst",     scope: :user, limit: 20,  window: 10.seconds),
        rule("sustained", scope: :user, limit: 300, window: 1.hour)
      ],

      # 🔥 Hook / D8N Opener sends: HooksController and OpenersController both
      # call Hooks::SendHook, which already enforces its own rolling daily
      # product allowance (Hooks::Policy, brand-configurable but 10/24h by
      # default) — that stays authoritative for "has this member used up
      # their day", and this layer never overrides its `hook_rate_limited`
      # error once the allowance is genuinely exhausted.
      #
      # But a burst ceiling ABOVE the daily allowance protects nothing (a
      # script can already exhaust 10/day in under a second). The point of
      # this bucket is the opposite: force rapid sends to spread out even
      # WITHIN the daily allowance — five scripted sends in one second is
      # abusive regardless of the eventual daily total. `sustained` is set
      # just above the daily allowance (never exactly 10) so a member who
      # paces their ten sends across the day is never accidentally blocked
      # by this layer before Hooks::Policy's own daily check would apply.
      send_hook: [
        rule("burst",     scope: :user, limit: 5,  window: 10.minutes),
        rule("sustained", scope: :user, limit: 15, window: 1.hour)
      ],

      # Chat media upload intents are expensive downstream (R2 objects, HEAD
      # verify, and — for video — a full-file async structural walk). Mirrors
      # media_upload_intent's shape; kept as its own bucket rather than shared
      # with profile-photo intents because the two surfaces have different
      # abuse profiles (one conversation vs. onboarding a photo set).
      chat_media_upload_intent: [
        rule("burst",     scope: :user, limit: 20,  window: 1.minute),
        rule("sustained", scope: :user, limit: 120, window: 1.hour),
        rule("ip",        scope: :ip,   limit: 300, window: 1.hour)
      ],
      # Finalizing (attaching) a verified attachment into a sent message. This
      # is IN ADDITION TO send_message on the same request — a media send
      # still counts against the ordinary messaging burst/sustained ceilings,
      # this only adds the extra media-specific ceiling on top.
      chat_media_attach: [
        rule("burst",     scope: :user, limit: 20,  window: 1.minute),
        rule("sustained", scope: :user, limit: 120, window: 1.hour)
      ]
    }.freeze

    class UnknownAction < StandardError; end

    def self.rules_for(action)
      RULES.fetch(action) { raise UnknownAction, "unknown abuse-protection action: #{action}" }
    end
  end
end
