module Migration
  # One source attachment/use, identified canonically by
  # (source_system, source_attachment_id). References exactly one
  # MediaObjectRef; a single blob may be referenced by many of these when the
  # source reused it (ADR 0027).
  #
  # Records the SOURCE use relationship (which source record used the blob, under
  # what attachment name). It never records the D8N destination — that binding is
  # Migration::ReferenceMap's job, and is created in pass 2.
  class MediaAttachmentRef < ApplicationRecord
    self.table_name = "migration_media_attachment_refs"

    belongs_to :media_object_ref, class_name: "Migration::MediaObjectRef", inverse_of: :media_attachment_refs

    enum :preflight_state, { pending: 0, preflighted: 1, owner_not_imported: 2, failed: 3 }, prefix: :preflight

    validates :source_system, :source_attachment_id, :source_record_entity, :source_record_id,
      :attachment_name, :importer_version, presence: true
    validates :source_system, :source_attachment_id, :source_record_id, :importer_version,
      length: { maximum: 255 }
    validates :source_system, format: { with: /\A[a-z][a-z0-9_]*\z/ }
    validates :source_record_entity, format: { with: /\A[a-z][a-z0-9_]*\z/ }, length: { maximum: 64 }
    validates :attachment_name, length: { maximum: 255 }
    validates :source_attachment_id, uniqueness: { scope: :source_system }

    # Raised when a rerun sees the same source attachment id pointing at a
    # different blob / source record / name — fail closed.
    class Drift < StandardError; end

    IDENTITY_FIELDS = %i[media_object_ref_id source_record_entity source_record_id attachment_name].freeze

    # Idempotent upsert keyed on (source_system, source_attachment_id).
    # Returns [ref, :created | :updated | :unchanged]. Any identity drift raises Drift.
    def self.record!(source_system:, source_attachment_id:, media_object_ref:, source_record_entity:,
      source_record_id:, attachment_name:, importer_version:, preflight_state: :preflighted, failure_code: nil)
      identity = {
        media_object_ref_id: media_object_ref.id,
        source_record_entity: source_record_entity.to_s,
        source_record_id: source_record_id.to_s,
        attachment_name: attachment_name.to_s
      }

      transaction do
        existing = lock.find_by(source_system:, source_attachment_id:)
        if existing
          if identity.any? { |field, value| existing.public_send(field) != value }
            raise Drift, "source attachment #{source_system.inspect} now points at a different object/record"
          end

          if existing.preflight_owner_not_imported? && preflight_state.to_sym == :preflighted
            existing.update!(preflight_state: :preflighted, failure_code: nil, importer_version:)
            return [ existing, :updated ]
          end

          return [ existing, :unchanged ]
        end

        [ create!(source_system:, source_attachment_id:, importer_version:, preflight_state:, failure_code:, **identity), :created ]
      end
    rescue ActiveRecord::RecordNotUnique
      existing = find_by!(source_system:, source_attachment_id:)
      if identity.any? { |field, value| existing.public_send(field) != value }
        raise Drift, "source attachment #{source_system.inspect} now points at a different object/record"
      end

      [ existing, :unchanged ]
    end

    def inspect
      "#<Migration::MediaAttachmentRef id=#{id.inspect}>"
    end
  end
end
