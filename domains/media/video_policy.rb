module Media
  # Per-brand profile-video policy, read from the brand contract's optional
  # VideoConfiguration (ADR 0023). Mirrors Media::PhotoPolicy: `status` tracks
  # the moderation lifecycle, `visibility` tracks whether the video may be shown,
  # and the two are orthogonal.
  #
  # A brand with no video configuration has no profile-video capability at all —
  # every accessor fails closed.
  class VideoPolicy
    DEFAULT_MAX_DURATION_SECONDS = 60
    DEFAULT_MAX_BYTE_SIZE = 50.megabytes
    ALLOWED_CONTENT_TYPES = ProfileVideo::ALLOWED_CONTENT_TYPES

    InitialState = Data.define(:status, :visibility)
    IMMEDIATE = InitialState.new(status: :pending_review, visibility: :visible)
    MODERATE_FIRST = InitialState.new(status: :pending_review, visibility: :hidden)

    class NotConfigured < StandardError; end

    class << self
      def enabled?(brand:)
        config(brand:).present?
      rescue D8n::Platform::BrandRegistry::UnsupportedBrand
        false
      end

      def initial_state(brand:)
        config!(brand:).initial_visibility == :immediate ? IMMEDIATE : MODERATE_FIRST
      end

      def max_duration_seconds(brand:)
        config!(brand:).max_duration_seconds
      end

      def max_byte_size(brand:)
        config!(brand:).max_byte_size
      end

      # ProfileVideo passes `self` here so publication logic lives in one place,
      # matching Media::PhotoPolicy.publication_eligible?.
      def publication_eligible?(video:)
        return false unless video.safe_derivative_ready?
        return false if video.rejected?
        return video.visible? if video.approved?

        moderate_first?(brand: video.brand) || video.visible?
      end

      def moderate_first?(brand:)
        config!(brand:).initial_visibility != :immediate
      end

      private

      def config(brand:)
        D8n::Platform::BrandRegistry.fetch(brand:).media.video
      end

      def config!(brand:)
        config(brand:) || raise(NotConfigured, "profile video is not configured for this brand")
      rescue D8n::Platform::BrandRegistry::UnsupportedBrand
        raise NotConfigured, "profile video is not configured for this brand"
      end
    end
  end
end
