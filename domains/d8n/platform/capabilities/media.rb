module D8n
  module Platform
    module Capabilities
      module Media
        DEFINITIONS = [
          CapabilityDefinition.new(key: "media.profile_photo.upload", status: :available,
            implementations: %w[Profiles::PhotoUpload]),
          CapabilityDefinition.new(key: "media.profile_photo.attach", status: :available,
            implementations: %w[Profiles::PhotoLibrary Profiles::PhotoUpload]),
          CapabilityDefinition.new(key: "media.profile_photo.process", status: :available,
            implementations: %w[Media::ImageProcessor Media::ProcessProfilePhotoJob]),
          CapabilityDefinition.new(key: "media.profile_photo.deliver", status: :available,
            implementations: %w[Profiles::PhotoLibrary Media::StorageResolver]),
          CapabilityDefinition.new(key: "media.profile_photo.delete", status: :available,
            implementations: %w[Profiles::PhotoLibrary Media::PurgeProfileMediaJob]),
          CapabilityDefinition.new(key: "media.profile_photo.moderation", status: :partial,
            implementations: %w[Media::PhotoPolicy ProfilePhoto],
            limitations: "Moderation states exist but a complete review workflow is not implemented."),
          CapabilityDefinition.new(key: "media.profile_video.upload", status: :available,
            implementations: %w[Profiles::VideoUpload Media::ObjectKey]),
          CapabilityDefinition.new(key: "media.profile_video.attach", status: :available,
            implementations: %w[Profiles::VideoUpload Media::VideoContainerValidator]),
          CapabilityDefinition.new(key: "media.profile_video.process", status: :available,
            implementations: %w[Media::ProcessProfileVideoJob Media::VideoProcessor]),
          CapabilityDefinition.new(key: "media.profile_video.deliver", status: :available,
            implementations: %w[Profiles::VideoLibrary Media::StorageResolver]),
          CapabilityDefinition.new(key: "media.profile_video.delete", status: :available,
            implementations: %w[Profiles::VideoLibrary]),
          CapabilityDefinition.new(key: "media.profile_video.moderation", status: :partial,
            implementations: %w[Media::VideoPolicy ProfileVideo],
            limitations: "Moderation states exist; the admin review action is shared with photo moderation."),
          CapabilityDefinition.new(key: "media.video", status: :planned)
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
