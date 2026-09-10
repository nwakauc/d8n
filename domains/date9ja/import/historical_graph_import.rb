# frozen_string_literal: true

require "digest"

module Date9ja
  module Import
    # Imports retained Date9ja relationship/history rows directly into the
    # canonical D8N graph. It deliberately does not call runtime interaction
    # services: historical rows must not emit notifications, consume limits, or
    # receive today's timestamps. Sources are deterministic enumerable objects
    # (the production adapter can be backed by the isolated snapshot; tests use
    # arrays of hashes).
    class HistoricalGraphImport
      SOURCE_SYSTEM = "date9ja"
      IMPORTER_VERSION = "date9ja-historical-graph-v1"
      ENTITIES = %i[likes passes matches conversations messages blocks reports].freeze

      Source = Data.define(*ENTITIES) do
        def self.empty = new(**ENTITIES.to_h { |key| [ key, [] ] })
      end
      Result = Data.define(:counts, :reasons)

      def self.call(brand:, source:, importer_version: IMPORTER_VERSION, excluded_source_ids: nil)
        new(brand:, source:, importer_version:, excluded_source_ids:).call
      end

      def initialize(brand:, source:, importer_version:, excluded_source_ids: nil)
        @brand = brand
        @source = source.is_a?(Hash) ? Source.new(**Source.empty.to_h.merge(source.symbolize_keys)) : source
        @version = importer_version
        # Date9ja source USER ids (== profile source ids) that must never appear
        # on a migrated relationship. Production discovery excludes seed/demo
        # accounts (§5), so a like/match/message that touches one is dropped
        # here with an explicit reason rather than silently over-imported.
        # The set is taken from the source adapter when it can supply it.
        supplied = excluded_source_ids
        supplied ||= source.excluded_participant_ids if source.respond_to?(:excluded_participant_ids)
        @excluded = Array(supplied).map(&:to_s).to_set
        @counts = Hash.new(0)
        @reasons = Hash.new(0)
      end

      def call
        assert_brand!
        each_row(:likes) { |row| import_like(row) }
        each_row(:passes) { |row| import_pass(row) }
        each_row(:matches) { |row| import_match(row) }
        each_row(:conversations) { |row| import_conversation(row) }
        each_row(:messages) { |row| import_message(row) }
        each_row(:blocks) { |row| import_block(row) }
        each_row(:reports) { |row| import_report(row) }
        Result.new(counts: counts.dup, reasons: reasons.dup)
      end

      private

      attr_reader :brand, :source, :version, :counts, :reasons

      def assert_brand!
        raise ArgumentError, "historical import requires Date9ja" unless brand&.slug == SOURCE_SYSTEM
      end

      def each_row(entity)
        Array(source.public_send(entity)).sort_by { |row| value(row, :id).to_i }.each do |row|
          bump(entity, :considered)
          begin
            ActiveRecord::Base.transaction(requires_new: true) { yield row }
          rescue MissingParticipant
            bump(entity, :skipped)
            reason(entity, "participant_not_migrated")
          rescue UnsupportedRow => error
            bump(entity, :skipped)
            reason(entity, error.code)
          rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
            bump(entity, :failed)
            reason(entity, "destination_conflict")
          rescue StandardError
            bump(entity, :failed)
            reason(entity, "invalid_source_reference")
          end
        end
      end

      class MissingParticipant < StandardError; end
      class UnsupportedRow < StandardError
        attr_reader :code
        def initialize(code) = (@code = code)
      end

      def import_like(row)
        return bump(:likes, :already_imported) if bound_record(:like, row)
        a, b = profiles(row, :liker_profile_id, :liked_profile_id)
        record = Like.find_or_initialize_by(brand:, liker_profile: a, liked_profile: b)
        unless record.new_record?
          bind!(record, :like, row)
          return bump(:likes, :already_imported)
        end
        record.assign_attributes(kind: value(row, :kind).presence || :like,
          created_at: timestamp(row), updated_at: timestamp(row), deleted_at: value(row, :deleted_at))
        record.save!
        bind!(record, :like, row)
        bump(:likes, :imported)
      end

      def import_pass(row)
        return bump(:passes, :already_imported) if bound_record(:profile_pass, row)
        a, b = profiles(row, :passer_profile_id, :passed_profile_id)
        record = ProfilePass.find_or_initialize_by(brand:, passer_profile: a, passed_profile: b)
        unless record.new_record?
          bind!(record, :profile_pass, row)
          return bump(:passes, :already_imported)
        end
        record.assign_attributes(created_at: timestamp(row), updated_at: timestamp(row), deleted_at: value(row, :deleted_at))
        record.save!
        bind!(record, :profile_pass, row)
        bump(:passes, :imported)
      end

      def import_match(row)
        return bump(:matches, :already_imported) if bound_record(:match, row)
        a, b = profiles(row, :profile_a_id, :profile_b_id, canonical: true)
        record = Match.find_or_initialize_by(brand:, profile_a: a, profile_b: b)
        unless record.new_record?
          bind!(record, :match, row)
          return bump(:matches, :already_imported)
        end
        record.assign_attributes(status: value(row, :status).presence || :active,
          created_at: timestamp(row), updated_at: timestamp(row), deleted_at: value(row, :deleted_at))
        record.save!
        bind!(record, :match, row)
        bump(:matches, :imported)
      end

      def import_conversation(row)
        match = resolve(:match, value(row, :match_id))
        raise MissingParticipant unless match
        record = Conversation.find_or_initialize_by(match:)
        unless record.new_record?
          bind!(record, :conversation, row)
          return bump(:conversations, :already_imported)
        end
        record.assign_attributes(brand:, status: value(row, :status).presence || :active,
          created_at: timestamp(row), updated_at: timestamp(row), deleted_at: value(row, :deleted_at))
        record.save!
        [ match.profile_a, match.profile_b ].each do |profile|
          record.conversation_participants.create!(profile:, user: profile.user, brand:, created_at: record.created_at, updated_at: record.updated_at)
        end
        bind!(record, :conversation, row)
        bump(:conversations, :imported)
      end

      def import_message(row)
        return bump(:messages, :already_imported) if bound_record(:message, row)
        conversation = resolve(:conversation, value(row, :conversation_id))
        sender = resolve_profile(value(row, :sender_profile_id))
        raise MissingParticipant unless conversation && sender
        source_id = integer_source_id!(value(row, :id), "invalid_source_message_id")
        body = value(row, :body)
        message_type = (value(row, :message_type) || value(row, :kind) || "text").to_s.downcase
        kind = Message.kinds.key?(message_type) ? message_type : { "super_like" => "text" }.fetch(message_type, nil)
        raise UnsupportedRow, "unsupported_message_type" if kind.nil?
        raise UnsupportedRow, "invalid_message_body" if body.blank? && value(row, :attachment_reference).blank?
        record = Message.new(brand:, conversation:, sender_profile: sender, body:,
          kind:, reply_to_message: resolve(:message, value(row, :reply_to_id)),
          read_at: value(row, :read_at), edited_at: value(row, :edited_at),
          source_media_reference: value(row, :attachment_reference),
          source_metadata: {
            "source_kind" => message_type,
            "media_checksum" => value(row, :attachment_checksum),
            "media_byte_size" => value(row, :attachment_byte_size),
            "media_content_type" => value(row, :attachment_content_type),
            "media_bytes_transferred" => (false if value(row, :attachment_reference).present?)
          }.compact,
          created_at: timestamp(row), updated_at: timestamp(row), deleted_at: value(row, :deleted_at))
        record.save!
        bind!(record, :message, row)
        bump(:messages, :imported)
      end

      def import_block(row)
        return bump(:blocks, :already_imported) if bound_record(:profile_block, row)
        a, b = profiles(row, :blocker_profile_id, :blocked_profile_id)
        record = ProfileBlock.find_or_initialize_by(brand:, blocker_profile: a, blocked_profile: b)
        unless record.new_record?
          bind!(record, :profile_block, row)
          return bump(:blocks, :already_imported)
        end
        record.assign_attributes(created_at: timestamp(row), updated_at: timestamp(row), deleted_at: value(row, :deleted_at))
        record.save!
        bind!(record, :profile_block, row)
        bump(:blocks, :imported)
      end

      def import_report(row)
        return bump(:reports, :already_imported) if bound_record(:report, row)
        reporter, reported = profiles(row, :reporter_profile_id, :reported_profile_id)
        target_type = value(row, :target_type).presence || :profile
        raise UnsupportedRow, "unsupported_report_target" unless Report.target_types.key?(target_type.to_s)
        reason = value(row, :reason).presence || :other
        raise UnsupportedRow, "unsupported_report_reason" unless Report.reasons.key?(reason.to_s)
        resolved_at = value(row, :resolved_at)
        status = if value(row, :status).present? then value(row, :status)
        elsif resolved_at.present? then :dismissed # Date9ja terminal "resolved"; outcome not recorded in source
        else :open
        end
        evidence = {
          "source_system" => "date9ja",
          "source_category" => value(row, :source_category),
          "source_resolved_at" => resolved_at&.then { |v| v.respond_to?(:iso8601) ? v.iso8601 : v.to_s },
          "source_resolution" => ("resolved_outcome_unknown" if resolved_at.present?)
        }.compact
        attrs = { brand:, reporter_profile: reporter, reported_profile: reported,
                  target_type:, target_id: value(row, :target_id), reason:,
                  status:, note: nil, evidence: }
        record = Report.new(attrs.merge(created_at: timestamp(row), updated_at: timestamp(row)))
        record.save!
        bind!(record, :report, row)
        bump(:reports, :imported)
      end

      def profiles(row, first_key, second_key, canonical: false)
        first = resolve_profile(value(row, first_key))
        second = resolve_profile(value(row, second_key))
        raise MissingParticipant unless first && second && first.id != second.id
        canonical ? Match.canonical_pair(first.id, second.id).map { |id| Profile.find(id) } : [ first, second ]
      end

      def resolve_profile(source_id)
        raise UnsupportedRow, "seed_linked_participant" if source_id.present? && @excluded.include?(source_id.to_s)

        resolve(:profile, source_id)
      end

      def resolve(entity, source_id)
        return nil if source_id.blank?
        record = Migration::ReferenceMap.resolved(source_system: SOURCE_SYSTEM, source_entity: entity.to_s, source_id: source_id)
        return nil unless record
        raise UnsupportedRow, "brand_mismatch" if record.respond_to?(:brand_id) && record.brand_id != brand.id
        record
      end

      def bound_record(entity, row)
        record = Migration::ReferenceMap.resolved(source_system: SOURCE_SYSTEM, source_entity: entity.to_s,
          source_id: value(row, :id))
        raise UnsupportedRow, "brand_mismatch" if record&.respond_to?(:brand_id) && record.brand_id != brand.id
        record
      end

      def bind!(record, entity, row)
        Migration::ReferenceMap.bind!(source_system: SOURCE_SYSTEM, source_entity: entity.to_s,
          source_id: value(row, :id), destination: record, brand:, importer_version: version,
          fingerprint: Digest::SHA256.hexdigest(row.to_h.sort_by { |k, _| k.to_s }.to_s)[0, 32])
      end

      def value(row, key)
        row[key] || row[key.to_s]
      end

      def timestamp(row)
        value(row, :created_at) || (raise UnsupportedRow, "missing_created_at")
      end

      def integer_source_id!(source_id, code)
        value = source_id.to_s
        raise UnsupportedRow, code unless value.match?(/\A\d+\z/)
        value
      end

      def bump(entity, state)
        counts["#{entity}.#{state}"] += 1
      end

      def reason(entity, code)
        reasons["#{entity}.#{code}"] += 1
      end
    end
  end
end
