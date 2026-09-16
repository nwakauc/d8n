module Profiles
  # Viewer-facing RICH profile detail for GET /profiles/:id. Extends the lean
  # PublicSerializer (used by discovery/matches/conversations) with the heavier
  # sections that belong on a single profile view — prompts, a categorized
  # interests view, and any matches_only option groups — so discovery cards stay
  # light while detail is expressive (ADR 0017).
  #
  # matches_only groups (e.g. intimacy preferences) are included ONLY when an
  # active Match exists between the viewer and the profile. Broader reachability
  # (brand isolation, active/visible lifecycle, blocks in either direction) is
  # already enforced upstream by Profiles::PublicProfile / Matching::VisibilityScope
  # before this serializer runs, so a blocked/closed relationship never reaches
  # here; requiring an ACTIVE match on top of that means an ended match hides them.
  class DetailSerializer
    def self.call(profile:, viewer:)
      new(profile:, viewer:).call
    end

    def initialize(profile:, viewer:)
      @profile = profile
      @viewer = viewer
    end

    def call
      # Scalar fields (and their fail-closed public audience resolution) come
      # entirely from PublicSerializer / FieldPolicy — detail adds only the
      # heavier non-scalar sections below.
      base = PublicSerializer.call(profile:)
      base[:options] = base[:options].merge(matches_only_options) if matched?

      base.merge(
        prompts: PromptPresenter.call(profile:),
        interests: grouped_interests
      ).merge(video_section)
    end

    private

    attr_reader :profile, :viewer

    # Intro video is a shared D8N Media capability (ADR 0023) surfaced on the
    # full profile view only — discovery/match/conversation cards stay lean.
    # The key is present solely for brands that enable the profile-video
    # capability, so DateZA / HookUs responses are unchanged. The payload is
    # (re)authorized at read time by Profiles::VideoLibrary + Media::VideoPolicy
    # (ADR 0011 delivery-time recheck): a video that is deleted, unprocessed,
    # failed, hidden, or no longer publication-eligible resolves to null and
    # never leaks a raw object key or unsigned URL.
    def video_section
      return {} unless Media::VideoPolicy.enabled?(brand: profile.brand)

      video = current_video
      { video: video&.brand_id == profile.brand_id ? VideoLibrary.public_payload(video) : nil }
    end

    def current_video
      if profile.association(:profile_video).loaded?
        profile.profile_video
      else
        ProfileVideo.kept.find_by(profile:)
      end
    end

    # Selections in still-visible groups, kept, with their option + group loaded.
    def visible_selections
      @visible_selections ||= if profile.profile_option_selections.loaded?
        profile.profile_option_selections.select do |selection|
          selection.deleted_at.nil? && selection.profile_option_group.deleted_at.nil?
        end
      else
        profile.profile_option_selections.kept.includes(:profile_option, :profile_option_group)
      end
    end

    def matches_only_options
      selections = visible_selections.select { |selection| selection.profile_option_group.visibility_matches_only? }
      group_codes(selections)
    end

    # A flat, categorized interests view built from the `interests` group's
    # selections, e.g. [{ slug:, label:, category: }]. Empty unless the brand
    # enables an `interests` group and the member has selections in it.
    def grouped_interests
      selections = visible_selections.select do |selection|
        selection.profile_option_group.key == "interests" &&
          selection.profile_option_group.visibility_public_profile?
      end

      selections.sort_by { |selection| [ selection.profile_option.position, selection.profile_option.id ] }
        .map do |selection|
          option = selection.profile_option
          { slug: option.code, label: option.label, category: option.category }
        end
    end

    def group_codes(selections)
      selections.group_by { |selection| selection.profile_option_group.key }.transform_values do |group_selections|
        group_selections.sort_by { |selection| [ selection.profile_option.position, selection.profile_option.id ] }
          .map { |selection| selection.profile_option.code }
      end
    end

    def matched?
      return false if viewer.nil? || viewer.id == profile.id

      first_id, second_id = Match.canonical_pair(viewer.id, profile.id)
      Match.kept.status_active.exists?(
        brand_id: profile.brand_id, profile_a_id: first_id, profile_b_id: second_id
      )
    end
  end
end
