module Date9ja
  module Import
    # Protected artifact: contains credentials/private values. Never log its
    # body. Export only on isolated rehearsal databases, with mode 0600.
    module SyncBundle
      VERSION = 1
      module_function

      def export(brand:)
        raise FinalSync::Conflict, "production_export_forbidden" if Rails.env.production?
        raise FinalSync::Conflict, "wrong_brand" unless brand.slug == "date9ja"

        refs = LegacyReference.for_source("date9ja").where(brand_id: [ nil, brand.id ]).to_a
        index = refs.index_by { |ref| [ ref.destination_type, ref.destination_id ] }
        rows = refs.sort_by { |ref| [ SyncPolicy::FIELDS.keys.index(ref.destination_type) || 999, ref.destination_id ] }.map do |ref|
          record = ref.destination || raise(FinalSync::Conflict, "dangling_export_binding")
          # Null reference ownership does not imply brandless identifiers.
          if record.respond_to?(:brand_id) && record.brand_id != brand.id
            raise FinalSync::Conflict, "cross_brand_export"
          end
          attrs = record.attributes.slice(*SyncPolicy.fields(ref.destination_type))
          record.class.reflect_on_all_associations(:belongs_to).each do |association|
            field = association.foreign_key.to_s
            next unless attrs[field]

            attrs[field] = association.klass == Brand ? { "$brand" => true } :
              dependency(index, association.klass.name, attrs[field])
          end
          if record.is_a?(Report) && record.target_id
            types = { "message" => "Message", "profile_media" => "ProfilePhoto", "conversation" => "Conversation" }
            attrs["target_id"] = dependency(index, types.fetch(record.target_type), record.target_id)
          end
          { "key" => [ ref.source_entity, ref.source_id ], "type" => ref.destination_type,
            "attributes" => attrs.as_json, "created_at" => record.created_at&.iso8601(6) }
        end
        passwords = refs.select { |ref| ref.destination_type == "Credential" }.filter_map do |ref|
          hash = ref.destination.credential_password_hash
          next unless hash

          { "key" => [ ref.source_entity, ref.source_id ],
            "attributes" => hash.attributes.slice("password_hash", "password_changed_at", "credential_kind").as_json }
        end
        options = refs.select { |ref| ref.destination_type == "Profile" }.map do |ref|
          values = ProfileOptionSelection.kept.where(brand:, profile_id: ref.destination_id)
            .includes(:profile_option_group, :profile_option).map do |selection|
              [ selection.profile_option_group.key, selection.profile_option.code ]
            end.sort
          { "key" => [ ref.source_entity, ref.source_id ], "values" => values }
        end
        { "version" => VERSION, "rows" => rows, "passwords" => passwords,
          "options" => options, "removals" => [] }
      end

      def dependency(index, type, id)
        ref = index[[ type, id ]] || raise(FinalSync::Conflict, "unbound_export_dependency")
        { "$ref" => [ ref.source_entity, ref.source_id ] }
      end

      def validate!(bundle)
        raise FinalSync::Conflict, "bundle_version" unless bundle.fetch("version") == VERSION
        seen = {}
        bundle.fetch("rows").each do |row|
          key = row.fetch("key")
          raise FinalSync::Conflict, "invalid_source_key" unless key.is_a?(Array) && key.size == 2 &&
            Migration::SourceSystems.valid_entity?(key[0]) && key[1].is_a?(String) && key[1].present?
          raise FinalSync::Conflict, "duplicate_source_key" if seen[key]

          seen[key] = true
          type = row.fetch("type")
          unknown = row.fetch("attributes").keys - SyncPolicy.fields(type)
          raise FinalSync::Conflict, "unsupported_attribute" if unknown.present?

          row.fetch("attributes").each do |field, value|
            next unless field.end_with?("_id") && value.present?
            next if field == "source_id" # explicit legacy namespace, not a destination FK

            valid = value == { "$brand" => true } ||
              (value.is_a?(Hash) && value.keys == [ "$ref" ] && value["$ref"].is_a?(Array) && value["$ref"].size == 2)
            raise FinalSync::Conflict, "numeric_destination_id_forbidden" unless valid
          end
        end
        %w[passwords options removals].each { |field| raise FinalSync::Conflict, "bundle_incomplete" unless bundle[field].is_a?(Array) }
      end

      def sync_children!(brand:, baseline:, desired:, resolved:, counts:)
        sync_passwords!(brand:, baseline:, desired:, resolved:, counts:)
        resolved.values.grep(Credential).select(&:password?).each do |credential|
          raise FinalSync::Conflict, "password_hash_incomplete" unless credential.credential_password_hash
        end
        sync_options!(brand:, baseline:, desired:, resolved:, counts:)
        resolved.values.grep(Conversation).each do |conversation|
          match = conversation.match
          [ match.profile_a, match.profile_b ].each do |profile|
            raise FinalSync::Conflict, "cross_brand_participant" unless profile.brand_id == brand.id
            next if ConversationParticipant.exists?(brand:, conversation:, profile:)

            ConversationParticipant.create!(brand:, conversation:, profile:, user: profile.user)
            counts["participants.created"] += 1
          end
        end
      end

      def sync_passwords!(brand:, baseline:, desired:, resolved:, counts:)
        before = baseline.fetch("passwords").index_by { |entry| entry.fetch("key") }
        desired.fetch("passwords").each do |entry|
          key = entry.fetch("key")
          credential = resolved.fetch(key)
          raise FinalSync::Conflict, "password_owner" unless credential.is_a?(Credential) &&
            credential.password? && credential.identity_identifier.brand_id == brand.id
          hash = credential.credential_password_hash
          attrs = entry.fetch("attributes")
          allowed = %w[password_hash password_changed_at credential_kind]
          raise FinalSync::Conflict, "password_attributes" if (attrs.keys - allowed).present?
          raise FinalSync::Conflict, "password_timestamp_missing" if attrs["password_changed_at"].blank?
          raise FinalSync::Conflict, "password_hash_invalid" unless IdentityImport::BCRYPT_RE.match?(attrs.fetch("password_hash"))

          current = hash&.password_hash
          final = attrs.fetch("password_hash")
          next if current == final
          old = before[key]&.dig("attributes", "password_hash")
          next if old == final # unchanged source must retain native recovery
          raise FinalSync::Conflict, "concurrent_password_change" unless current == old

          hash ? hash.update!(attrs) : CredentialPasswordHash.create!(attrs.merge("credential" => credential))
          Session.active.where(brand:, credential:).find_each { |session| Identity::SessionRevoker.call(session:) }
          counts["passwords.updated"] += 1
        end
      end

      def sync_options!(brand:, baseline:, desired:, resolved:, counts:)
        before = baseline.fetch("options").index_by { |entry| entry.fetch("key") }
        desired.fetch("options").each do |entry|
          key = entry.fetch("key")
          profile = resolved[key] || Migration::ReferenceMap.resolved(source_system: "date9ja",
            source_entity: key[0], source_id: key[1])
          next if desired.fetch("removals").any? { |removal| removal.fetch("key") == key }
          raise FinalSync::Conflict, "option_owner" unless profile.is_a?(Profile) && profile.brand_id == brand.id

          selections = ProfileOptionSelection.kept.where(brand:, profile:).includes(:profile_option_group, :profile_option).to_a
          current = selections.map { |selection| [ selection.profile_option_group.key, selection.profile_option.code ] }.sort
          final = entry.fetch("values").sort
          old = before[entry.fetch("key")]&.fetch("values")&.sort || []
          next if current == final || old == final
          raise FinalSync::Conflict, "concurrent_catalog_edit" unless current == old

          selections.each do |selection|
            pair = [ selection.profile_option_group.key, selection.profile_option.code ]
            selection.update!(deleted_at: Time.current) unless final.include?(pair)
          end
          (final - current).each do |group_key, code|
            group = ProfileOptionGroup.kept.find_by!(brand:, key: group_key)
            option = ProfileOption.kept.find_by!(brand:, profile_option_group: group, code:)
            ProfileOptionSelection.create!(brand:, user: profile.user, profile:, profile_option_group: group, profile_option: option)
          end
          counts["options.updated"] += 1
        end
      end
    end
  end
end
