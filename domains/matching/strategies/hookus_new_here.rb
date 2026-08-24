module Matching
  module Strategies
    # "New here" discovery mode for HookUs: the newest eligible profiles first.
    #
    # It deliberately reuses Strategies::Hookus for eligibility and for the
    # compatibility payload, so it never bypasses a discovery rule (brand
    # isolation, active/visible, current-user exclusion, reciprocal
    # age/gender/preference, distance, blocking/exclusions). The *only* change is
    # ordering: candidates are sorted by recency instead of match score, with a
    # deterministic (created_at, public_id) tiebreak.
    class HookusNewHere
      KEY = "hookus_new_here_v1"
      RECENCY_ORDER = "profiles.created_at DESC, profiles.public_id DESC".freeze

      def self.key
        KEY
      end

      def self.production_ready?
        true
      end

      # Same scored/eligible relation as the default feed — only re-sorted by
      # recency. Keeping Hookus's SELECT means the compatibility payload is
      # identical to "For You".
      def self.rank(scope:, viewer:, eligibility_policy:)
        Hookus.rank(scope:, viewer:, eligibility_policy:).reorder(Arel.sql(RECENCY_ORDER))
      end

      def self.compatibility(profile:)
        Hookus.compatibility(profile:)
      end

      # Recency ordering is fully captured by the cursor's base (created_at,
      # profile) fields, so this mode needs no extra ranking payload.
      def self.cursor_payload(profile:)
        {}
      end

      def self.apply_cursor(scope:, payload:)
        created_at = Time.iso8601(payload.fetch(:created_at))
        public_id = payload.fetch(:profile).to_s
        raise Cursor::Invalid, "cursor is invalid" unless public_id.match?(Profile::PUBLIC_ID_FORMAT)

        Profile.from(scope, :profiles).where(
          "profiles.created_at < :created_at OR " \
            "(profiles.created_at = :created_at AND profiles.public_id < :public_id)",
          created_at:, public_id:
        ).reorder(Arel.sql(RECENCY_ORDER))
      rescue ArgumentError, KeyError, TypeError
        raise Cursor::Invalid, "cursor is invalid"
      end
    end
  end
end
