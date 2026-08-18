module HookTonight
  # The Hook Tonight discovery pool: the exact same eligible discovery population
  # as Matching::Discovery (brand isolation, active/visible lifecycle, blocking in
  # either direction, reciprocal age/gender/orientation, distance/privacy, live-
  # Hook exclusion, ranking, cursor, safe photos, no N+1) narrowed to members who
  # ALSO have a live "available tonight" state.
  #
  # This intentionally does not fork the discovery engine — it injects a single
  # `restrict` clause. Everything downstream (viewer eligibility, exclusions,
  # facets, ranking, pagination, serialization) is unchanged, so Hook Tonight can
  # never surface someone normal discovery wouldn't, and location remains the same
  # privacy-preserving approximate distance discovery already uses.
  #
  # Approaching someone found here still goes through the existing 🔥 Hook flow;
  # this surface produces no matches, conversations, or messages of its own.
  #
  # Access is RECIPROCAL: to see who's available tonight you must be available
  # tonight. Members in the pool expose a sensitive "open to meet tonight" signal,
  # so browsing it while invisible is disallowed — a viewer without a live
  # activation gets NotActivated (surfaced as `hook_tonight_required`). Normal
  # discovery is unaffected and remains open to everyone.
  class Discovery
    class NotActivated < StandardError; end

    def self.call(user:, brand:, cursor: nil, limit: nil, mode: nil, vibe: nil, online: nil)
      Matching::Discovery.call(
        user:, brand:, cursor:, limit:, mode:, vibe:, online:,
        guard: ->(viewer) do
          raise NotActivated unless HookTonightState.live.exists?(brand:, profile: viewer)
        end,
        restrict: ->(scope, _viewer) do
          scope.where(id: HookTonightState.live.where(brand:).select(:profile_id))
        end
      )
    end
  end
end
