module Trust
  class BlockPolicy
    MATCH_EXCLUSION_SQL = <<~SQL.squish.freeze
      NOT EXISTS (
        SELECT 1
        FROM profile_blocks
        WHERE profile_blocks.brand_id = matches.brand_id
          AND profile_blocks.deleted_at IS NULL
          AND (
            (
              profile_blocks.blocker_profile_id = matches.profile_a_id
              AND profile_blocks.blocked_profile_id = matches.profile_b_id
            )
            OR (
              profile_blocks.blocker_profile_id = matches.profile_b_id
              AND profile_blocks.blocked_profile_id = matches.profile_a_id
            )
          )
      )
    SQL

    def self.exclude_profiles(scope:, viewer:)
      outgoing = ProfileBlock.kept.where(brand: viewer.brand, blocker_profile: viewer).select(:blocked_profile_id)
      incoming = ProfileBlock.kept.where(brand: viewer.brand, blocked_profile: viewer).select(:blocker_profile_id)

      scope.where.not(id: outgoing).where.not(id: incoming)
    end

    def self.exclude_matches(scope:)
      scope.where(MATCH_EXCLUSION_SQL)
    end

    def self.blocked_between?(brand:, first:, second:)
      outgoing = ProfileBlock.kept.where(
        brand:,
        blocker_profile: first,
        blocked_profile: second
      )
      incoming = ProfileBlock.kept.where(
        brand:,
        blocker_profile: second,
        blocked_profile: first
      )

      outgoing.or(incoming).exists?
    end
  end
end
