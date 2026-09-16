module Migration
  # Foreign systems D8N imports from. An unknown source system fails closed
  # (ADR 0022) so a typo can never create an unnamespaced binding.
  module SourceSystems
    KNOWN = %w[ date9ja ].freeze

    # Source entity names are source-shaped and numerous, so they are validated
    # by format rather than an exhaustive list.
    ENTITY_FORMAT = /\A[a-z][a-z0-9_]*\z/
    ENTITY_MAX_LENGTH = 64

    def self.known?(system)
      KNOWN.include?(system.to_s)
    end

    def self.valid_entity?(entity)
      value = entity.to_s
      value.length <= ENTITY_MAX_LENGTH && value.match?(ENTITY_FORMAT)
    end
  end
end
