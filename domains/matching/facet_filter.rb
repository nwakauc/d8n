module Matching
  # Optional discovery facets: they narrow the eligible candidate set without
  # touching ordering, so any discovery mode can be combined with any facet
  # (e.g. `?mode=new_here&vibe=420_friendly&online=true`). Facets never relax
  # eligibility — they are applied on top of the already-eligible scope.
  #
  # Supported facets:
  #   * vibe   — profiles that publicly selected a given "vibes" option
  #              (the HookUs "420 Friendly" control). Unknown code is a client
  #              error, not a silent empty feed.
  #   * online — profiles whose user has an active session used within
  #              ONLINE_WINDOW. `Session#last_used_at` is refreshed on every
  #              authenticated request, so this is a genuine recent-activity
  #              signal, not a placeholder.
  class FacetFilter
    class InvalidFilter < StandardError; end

    VIBES_GROUP = "vibes".freeze
    ONLINE_WINDOW = 10.minutes

    Filter = Data.define(:vibe, :online) do
      def none?
        vibe.nil? && !online
      end

      # Stable fingerprint bound into the pagination cursor so a later page
      # cannot silently drop or change a facet.
      def cursor_key
        parts = []
        parts << "vibe:#{vibe}" unless vibe.nil?
        parts << "online:1" if online
        parts.join("|")
      end
    end

    NONE = Filter.new(vibe: nil, online: false)

    def self.parse(brand:, vibe: nil, online: nil)
      Filter.new(vibe: parse_vibe(brand:, vibe:), online: truthy?(online))
    end

    def self.apply(scope:, brand:, filter:)
      scope = scope.where(id: matching_selections(brand:, code: filter.vibe)) unless filter.vibe.nil?
      scope = scope.where(user_id: online_user_ids(brand:)) if filter.online
      scope
    end

    def self.parse_vibe(brand:, vibe:)
      code = vibe.to_s.strip
      return nil if code.empty?
      raise InvalidFilter, "unknown vibe" unless filterable_vibe_codes(brand:).include?(code)

      code
    end
    private_class_method :parse_vibe

    def self.truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end
    private_class_method :truthy?

    def self.matching_selections(brand:, code:)
      ProfileOptionSelection.kept
        .where(brand:)
        .joins(:profile_option_group, :profile_option)
        .merge(ProfileOptionGroup.kept.status_active.visibility_public_profile)
        .merge(ProfileOption.kept.status_active)
        .where(profile_option_groups: { key: VIBES_GROUP })
        .where(profile_options: { code: })
        .select(:profile_id)
    end
    private_class_method :matching_selections

    def self.online_user_ids(brand:)
      Session.active
        .where(brand:, last_used_at: ONLINE_WINDOW.ago..)
        .select(:user_id)
    end
    private_class_method :online_user_ids

    def self.filterable_vibe_codes(brand:)
      ProfileOption.kept.status_active
        .joins(:profile_option_group)
        .merge(ProfileOptionGroup.kept.status_active.visibility_public_profile)
        .where(profile_option_groups: { brand:, key: VIBES_GROUP })
        .pluck(:code)
    end
    private_class_method :filterable_vibe_codes
  end
end
