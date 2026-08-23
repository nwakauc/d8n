require "digest"

module Profiles
  module DemoSeed
    # Persists ONE demo person into real, valid rows using the same models and
    # services a genuine member would — no discovery special-casing, no serializer
    # spoofing, no validation bypass. Every profile ends up active/visible only by
    # passing the real Profiles::Publication gate; photos become deliverable only
    # by running the real Media::ProcessProfilePhotoJob.
    #
    # Idempotent: identity is the caller-supplied seed email. A rerun
    # updates the existing profile in place, refreshes its location/activity, and
    # attaches only photos it hasn't attached before (tracked by source basename in
    # ProfilePhoto#metadata). Nothing external is sent — creating an identifier row
    # is not the verification flow, so no Resend/Twilio delivery is triggered.
    class Builder
      SEED_TAG = "hookus_demo".freeze
      SEED_DEVICE = "seed-demo".freeze
      VERIFIED_AT = 30.days
      NEW_HERE_AGE = 2.days
      ESTABLISHED_AGE = 30.days
      ACTIVITY_AGES = {
        online: 2.minutes, active_today: 5.hours, this_week: 3.days
      }.freeze
      CONTENT_TYPES = { ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
                        ".png" => "image/png", ".webp" => "image/webp" }.freeze

      Outcome = Data.define(:created, :photos_attached)

      def self.call(person:, content:, brand:, now: Time.current, email: person.email,
        seed_tag: SEED_TAG, identity_attributes: {}, seed_device: SEED_DEVICE, photo_initial_state: nil)
        new(
          person:, content:, brand:, now:, email:, seed_tag:,
          identity_attributes:, seed_device:, photo_initial_state:
        ).call
      end

      def initialize(person:, content:, brand:, now:, email:, seed_tag:, identity_attributes:, seed_device:,
        photo_initial_state:)
        @person = person
        @content = content
        @brand = brand
        @now = now
        @email = email
        @seed_tag = seed_tag
        @identity_attributes = identity_attributes
        @seed_device = seed_device
        @photo_initial_state = photo_initial_state
      end

      def call
        identifier = IdentityIdentifier.kept.find_by(kind: :email, normalized_value: email)
        created = identifier.nil?

        profile = ActiveRecord::Base.transaction do
          identifier ||= create_identity
          persist_core(identifier)
        end

        photos_attached = attach_photos(profile)
        Publication.activate!(user: profile.user, brand:)
        Outcome.new(created:, photos_attached:)
      end

      private

      attr_reader :person, :content, :brand, :now, :email, :seed_tag, :identity_attributes, :seed_device,
        :photo_initial_state

      def create_identity
        user = User.create!(identity_attributes.merge(status: :active))
        user.identity_identifiers.create!(
          kind: :email, normalized_value: email, last_seen_at: now,
          metadata: { "seed" => seed_tag }
        )
      end

      def persist_core(identifier)
        user = identifier.user
        user.update!(identity_attributes) if identity_attributes.any? && user.attributes.symbolize_keys.slice(*identity_attributes.keys) != identity_attributes
        identifier.update!(verified_at: content.verified ? (identifier.verified_at || now - VERIFIED_AT) : nil)
        membership = BrandMembership.kept.find_or_create_by!(user:, brand:) { |m| m.status = :active }
        membership.update!(status: :active) unless membership.active?

        profile = upsert_profile(user:, membership:)
        upsert_preference(profile:, user:)
        OptionSelections.replace!(profile:, selections: content.options)
        PromptAnswers.replace!(profile:, answers: content.prompts)
        upsert_location(profile:, user:)
        set_activity(user:)
        profile.update_column(:created_at, now - (content.new_here ? NEW_HERE_AGE : ESTABLISHED_AGE))
        profile
      end

      def upsert_profile(user:, membership:)
        profile = Profile.kept.find_or_initialize_by(user:, brand:)
        profile.brand_membership = membership
        profile.assign_attributes(content.profile.merge(birthdate: content.birthdate))
        profile.metadata = profile.metadata.merge("seed" => seed_tag, "seed_slug" => person.slug)
        # Draft until the real publication gate flips it live once complete.
        profile.status = :draft unless profile.active?
        profile.save!
        profile
      end

      def upsert_preference(profile:, user:)
        preference = ProfilePreference.kept.find_or_initialize_by(profile:)
        preference.assign_attributes(content.preference.merge(user:, brand:))
        preference.save!
      end

      def upsert_location(profile:, user:)
        location = ProfileLocation.kept.find_or_initialize_by(profile:)
        location.assign_attributes(
          user:, brand:, source: "device", accuracy_meters: 25, captured_at: now,
          **content.location
        )
        location.save!
      end

      # Reset the seed's synthetic presence so reruns re-assert the intended state
      # deterministically (an inactive member simply has no live seed session).
      def set_activity(user:)
        Session.where(user:, brand:, device_name: seed_device).delete_all
        age = ACTIVITY_AGES[content.activity]
        return if age.nil?

        Session.create!(
          user:, brand:, device_name: seed_device,
          token_digest: Session.digest_token(SecureRandom.urlsafe_base64(Session::TOKEN_BYTES)),
          last_used_at: now - age, expires_at: now + Session::DEFAULT_TTL
        )
      end

      # Attach any not-yet-seeded images for this person, preserving folder order
      # (first image is the primary/display shot), then run the real safe-derivative
      # pipeline so each photo is deliverable exactly like a member upload.
      def attach_photos(profile)
        existing = profile.profile_photos.kept.filter_map { |photo| photo.metadata["seed_basename"] }.to_set
        position = profile.profile_photos.kept.maximum(:position).to_i
        attached = 0

        person.image_paths.each do |path|
          basename = File.basename(path)
          next if existing.include?(basename)

          position += 1
          attach_photo(profile:, path:, basename:, position:)
          attached += 1
        end
        attached
      end

      def attach_photo(profile:, path:, basename:, position:)
        content_type = CONTENT_TYPES.fetch(File.extname(path).downcase)
        key = Media::ObjectKey.profile_photo_original(
          brand:, user: profile.user, profile:, content_type:
        )
        blob = ActiveStorage::Blob.create_and_upload!(
          io: File.open(path, "rb"), key:, filename: basename, content_type:,
          service_name: Media::StorageResolver.service_name(brand:)
        )
        initial = photo_initial_state || Media::PhotoPolicy.initial_state(brand:)
        photo = ProfilePhoto.new(
          profile:, user: profile.user, brand:, position:,
          status: initial.status, visibility: initial.visibility,
          metadata: { "seed" => seed_tag, "seed_basename" => basename }
        )
        photo.image.attach(blob)
        photo.save!
        # Synchronous so a seed run leaves photos already deliverable rather than
        # waiting on a background queue that staging may not be draining.
        Media::ProcessProfilePhotoJob.perform_now(photo.id)
      end
    end
  end
end
