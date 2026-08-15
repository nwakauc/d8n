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
    InitialState = Data.define(:status, :visibility)

    # Usable on upload; moderation runs afterwards.
    IMMEDIATE = InitialState.new(status: :pending_review, visibility: :visible)
    # Hidden until a moderation decision makes it visible.
    MODERATE_FIRST = InitialState.new(status: :pending_review, visibility: :hidden)

    BRAND_POLICIES = {
      "hookus" => IMMEDIATE
    }.freeze

    def self.initial_state(brand:)
      BRAND_POLICIES.fetch(brand.slug, MODERATE_FIRST)
    end
  end
end
