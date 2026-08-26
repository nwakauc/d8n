module Media
  # Per-brand initial visibility policy for a freshly attached profile photo.
  #
  # `status` tracks the moderation lifecycle (pending_review -> approved /
  # rejected); `visibility` tracks whether the photo may be shown. They are
  # orthogonal on purpose: a photo can be `visible` before a moderator or
  # automated check has approved it.
  #
  # HookUs treats an ordinary valid photo as usable immediately after attach
  # (`visible`) and moderates it asynchronously; if a later check flags it,
  # moderation flips it back to `hidden`/`rejected`. Any brand without an
  # explicit policy stays moderate-first (`hidden`, `pending_review`) so a new
  # brand never silently publishes unmoderated media. Date9ja therefore keeps the
  # conservative default until it opts in.
  #
  # Moderation capability is unchanged — this only decides the starting state.
  class PhotoPolicy
    DEFAULT_MAX_COUNT = 6
    InitialState = Data.define(:status, :visibility)

    # Usable on upload; moderation runs afterwards.
    IMMEDIATE = InitialState.new(status: :pending_review, visibility: :visible)
    # Hidden until a moderation decision makes it visible.
    MODERATE_FIRST = InitialState.new(status: :pending_review, visibility: :hidden)

    def self.initial_state(brand:)
      immediate?(brand:) ? IMMEDIATE : MODERATE_FIRST
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      MODERATE_FIRST
    end

    def self.max_count(brand:)
      Integer(D8n::Platform::BrandRegistry.fetch(brand:).media.max_profile_photos)
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand, ArgumentError, TypeError
      DEFAULT_MAX_COUNT
    end

    # Publication eligibility is deliberately broader than public delivery for
    # moderate-first brands. A processed, safe photo that is still legitimately
    # awaiting review may finish onboarding, but remains absent from every public
    # serializer until approval makes it visible. Terminal rejection, failed or
    # incomplete processing, deletion, and inconsistent terminal visibility all
    # fail closed.
    def self.publication_eligible?(photo:)
      return false unless photo.safe_derivative_ready?
      return false if photo.rejected?
      return photo.visible? if photo.approved?

      moderate_first?(brand: photo.brand) || photo.visible?
    end

    def self.immediate?(brand:)
      D8n::Platform::BrandRegistry.fetch(brand:).media.initial_visibility == :immediate
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      false
    end

    def self.moderate_first?(brand:)
      !immediate?(brand:)
    end
  end
end
