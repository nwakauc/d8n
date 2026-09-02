module Migration
  # The D8N record classes an importer may bind a legacy reference to, and
  # whether each is brand-owned (ADR 0022). A brand-owned destination requires a
  # matching `brand_id` on the binding; a platform destination requires none.
  #
  # This list grows one entry at a time as importer slices ship — it is not a
  # dump of every model. An unknown destination type fails closed.
  module DestinationTypes
    # Only the destinations an assigned importer slice actually needs. New rows
    # are added with the slice that imports them — not speculatively. Wave A
    # (identity + profile + profile media) is covered here; matching/messaging/
    # notification destinations arrive with their Wave B/C importer slices.
    OWNERSHIP = {
      # Platform identity (spans brands).
      "User" => :platform,
      "IdentityIdentifier" => :platform,
      # Brand-owned dating presence and media.
      "BrandMembership" => :brand_owned,
      "Profile" => :brand_owned,
      "ProfilePreference" => :brand_owned,
      "ProfilePhoto" => :brand_owned,
      "ProfileVideo" => :brand_owned
    }.freeze

    def self.known?(type)
      OWNERSHIP.key?(type.to_s)
    end

    def self.brand_owned?(type)
      OWNERSHIP[type.to_s] == :brand_owned
    end

    def self.platform?(type)
      OWNERSHIP[type.to_s] == :platform
    end
  end
end
