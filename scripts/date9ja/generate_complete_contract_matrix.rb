# frozen_string_literal: true

# Generates the mechanically exhaustive source inventory and one-row-per-column
# matrix embedded in COMPLETE-CONTRACT-AUDIT.md. This script is intentionally
# read-only with respect to PostgreSQL. It writes only the generated Markdown
# between the two marker pairs in the audit artifact.

require "pg"
require "uri"

SOURCE_URL = ENV.fetch("DATE9JA_SNAPSHOT_DATABASE_URL")
OUTPUT = File.expand_path("../../docs/migrations/date9ja-to-d8n/COMPLETE-CONTRACT-AUDIT.md", __dir__)

TABLES = {
  "users" => [ "identity", "Identity / Profiles / Trust", "IdentityImport; ProfilePreferenceImport; ProfileReadinessImport; SensitiveProfileImport", "User; BrandMembership; Profile; ProfilePreference; option selections" ],
  "phone_verifications" => [ "verification", "Identity", "GAP: no production importer", "IdentityIdentifier verified state / verification assertion" ],
  "selfie_verifications" => [ "verification", "Verification", "GAP: no production importer", "GAP: verification assertion and review history" ],
  "verification_checks" => [ "verification", "Verification", "GAP: no production importer", "GAP: verification assertion/evidence metadata" ],
  "verification_events" => [ "verification", "Verification", "GAP: no production importer", "GAP: immutable verification history" ],
  "trust_events" => [ "safety/moderation", "Trust", "GAP: no production importer", "GAP: trust ledger" ],
  "trust_adjustments" => [ "safety/moderation", "Trust", "GAP: no production importer", "GAP: trust adjustment/appeal ledger" ],
  "photos" => [ "media", "Media", "PhotoImport preflight; PhotoTransfer", "ProfilePhoto + Active Storage + migration media refs" ],
  "profile_videos" => [ "media", "Media", "VideoPreflight; VideoTransfer", "ProfileVideo + Active Storage + migration media refs" ],
  "active_storage_attachments" => [ "media", "Media", "Photo/Video preflight and transfer (profile media only)", "Active Storage attachment; non-profile attachment owners are gaps" ],
  "active_storage_blobs" => [ "media", "Media", "Photo/Video preflight and transfer (profile media only)", "Active Storage blob; non-profile attachment owners are gaps" ],
  "active_storage_variant_records" => [ "media", "Media", "RECONSTRUCT after transfer", "Derived media variant" ],
  "likes" => [ "likes/passes", "Matching", "HistoricalGraphImport", "Like" ],
  "profile_passes" => [ "likes/passes", "Matching", "HistoricalGraphImport", "ProfilePass" ],
  "matches" => [ "matches", "Matching", "HistoricalGraphImport", "Match + derived Conversation" ],
  "messages" => [ "messages", "Messaging", "HistoricalGraphImport (currently rejects integer kinds)", "Message; attachment/reply/read semantics have gaps" ],
  "message_reactions" => [ "messages", "Messaging", "GAP: no importer", "GAP: message reaction" ],
  "blocks" => [ "blocks", "Trust", "HistoricalGraphImport", "ProfileBlock" ],
  "reports" => [ "reports", "Trust", "HistoricalGraphImport (current vocabulary mismatch)", "Report; resolution/body/actor semantics have gaps" ],
  "profile_views" => [ "discovery", "Matching / Analytics", "GAP: no importer", "GAP: member-visible view history" ],
  "daily_introductions" => [ "discovery", "Matching", "GAP: no importer", "GAP: introduction/history record" ],
  "explore_impressions" => [ "discovery", "Matching / Analytics", "GAP: no importer", "GAP: impression/exhaustion history" ],
  "dating_hub_batches" => [ "discovery", "Matching", "GAP: no importer", "GAP: batch state" ],
  "notifications" => [ "notifications", "Notifications", "GAP: no importer", "GAP: in-app notification history" ],
  "notification_deliveries" => [ "notifications", "Notifications", "GAP: no importer", "GAP: delivery history" ],
  "push_tokens" => [ "notifications", "Notifications", "GAP: no cutover policy/importer", "DeviceRegistration or explicit revoke/re-enrol decision" ],
  "exit_attempts" => [ "lifecycle", "Identity / Analytics", "GAP: no importer", "GAP: exit/retention history" ],
  "audit_logs" => [ "admin/audit", "Admin / Trust", "GAP: no importer", "GAP: retained operator audit history" ],
  "aunty_phobie_conversations" => [ "messages", "Messaging / Trust", "GAP: no importer", "GAP: private assistant conversation/escalation" ],
  "aunty_phobie_messages" => [ "messages", "Messaging / Trust", "GAP: no importer", "GAP: private assistant message history" ],
  "aunty_phobie_usage_events" => [ "analytics/system-only", "Analytics", "GAP: no importer", "GAP: assistant quota/accounting history" ],
  "community_questions" => [ "profile", "Profiles", "GAP: no importer", "GAP: community content" ],
  "community_answers" => [ "profile", "Profiles", "GAP: no importer", "GAP: community content" ],
  "community_answer_votes" => [ "profile", "Profiles", "GAP: no importer", "GAP: community vote" ],
  "community_events" => [ "profile", "Profiles", "GAP: no importer", "GAP: community event" ],
  "community_event_rsvps" => [ "profile", "Profiles", "GAP: no importer", "GAP: member RSVP" ],
  "community_reports" => [ "safety/moderation", "Trust", "GAP: no importer", "GAP: community report" ],
  "community_stories" => [ "profile", "Profiles", "GAP: no importer", "GAP: community story" ],
  "community_remarks" => [ "profile", "Profiles", "GAP: no importer", "GAP: community remark" ],
  "personas" => [ "preference", "Profiles", "GAP: no importer", "GAP: dating persona" ],
  "daily_life_entries" => [ "profile", "Profiles", "GAP: no importer", "GAP: daily-life content" ],
  "tracked_contacts" => [ "profile", "Profiles", "GAP: no importer", "GAP: private tracked contact" ],
  "tracked_contact_notes" => [ "profile", "Profiles", "GAP: no importer", "GAP: private contact note" ],
  "career_applications" => [ "analytics/system-only", "System", "None", "Not member dating contract" ],
  "career_jobs" => [ "analytics/system-only", "System", "None", "Not member dating contract" ],
  "company_goals" => [ "analytics/system-only", "System", "None", "Internal company planning" ],
  "company_journal_entries" => [ "analytics/system-only", "System", "None", "Internal company planning" ],
  "company_settings" => [ "analytics/system-only", "System", "None", "Internal company planning" ],
  "feedback_items" => [ "admin/audit", "Admin", "GAP: retention/export decision", "GAP: member feedback record" ],
  "error_logs" => [ "analytics/system-only", "System", "None", "Operational telemetry; aggregate-only" ],
  "ar_internal_metadata" => [ "analytics/system-only", "System", "None", "Rails framework metadata" ],
  "schema_migrations" => [ "analytics/system-only", "System", "None", "Source schema version metadata" ]
}.freeze

IDENTITY_FIELDS = %w[email encrypted_password confirmed_at phone phone_verified_at public_id jti sign_in_count current_sign_in_at last_sign_in_at current_sign_in_ip last_sign_in_ip confirmation_token confirmation_sent_at unconfirmed_email reset_password_token reset_password_sent_at].freeze
PROFILE_FIELDS = %w[full_name display_name date_of_birth gender looking_for about_me city country_of_residence location_latitude location_longitude occupation ideal_partner_description body_type height willing_to_relocate relocation_preferences languages_spoken].freeze
PREFERENCE_FIELDS = %w[preferred_age_min preferred_age_max preferred_distance_km preferred_countries interests relationship_values dealbreakers education marital_status wants_children children_count relationship_intention commitment_timeline smoking drinking fitness family_involvement_preference].freeze
SENSITIVE_FIELDS = %w[is_nigerian state_of_origin nationality tribe ethnicity religion denomination genotype intertribal_marriage_openness polygamy_openness preferred_religion preferred_tribes preferred_ethnicity preferred_genotype interest_in_nigerian_culture].freeze
LIFECYCLE_FIELDS = %w[deleted_at deletion_reason deletion_reason_code deletion_comment suspended_at suspension_reason banned_at ban_reason profile_hidden discovery_restricted_at discovery_restriction_reason discovery_restriction_note discovery_restricted_by_id flagged_for_moderation_at onboarding_completed_at last_active_at].freeze

PSEUDONYMIZED = {
  "users" => %w[email encrypted_password full_name display_name phone public_id jti],
  "phone_verifications" => %w[phone], "push_tokens" => %w[token],
  "active_storage_blobs" => %w[key filename], "trust_events" => %w[idempotency_key],
  "trust_adjustments" => %w[idempotency_key], "aunty_phobie_usage_events" => %w[request_key],
  "career_applications" => %w[name email phone date9ja_email portfolio_url linkedin_url],
  "community_events" => %w[title], "community_stories" => %w[couple_names title],
  "dating_hub_batches" => %w[name], "tracked_contacts" => %w[external_name],
  "aunty_phobie_messages" => %w[client_message_id]
}.freeze
DESTROYED = {
  "users" => %w[unconfirmed_email reset_password_token reset_password_sent_at confirmation_token confirmation_sent_at current_sign_in_ip last_sign_in_ip location_latitude location_longitude tribe denomination state_of_origin nationality religion ethnicity intertribal_marriage_openness polygamy_openness is_nigerian],
  "phone_verifications" => %w[code_digest], "push_tokens" => %w[device_name],
  "verification_checks" => %w[provider provider_reference ai_review_model ai_review_error rejection_code],
  "active_storage_blobs" => %w[metadata],
  "community_events" => %w[venue], "community_stories" => %w[location],
  "tracked_contacts" => %w[external_location partner_birthday_month partner_birthday_day]
}.freeze
GENERALIZED = {
  "users" => %w[date_of_birth signup_source attribution_source attribution_medium attribution_campaign attribution_content device_type os_name browser_name notification_preferences email_notification_preferences body_type country_of_residence]
}.freeze
REDACTED = {
  "users" => %w[city about_me ideal_partner_description interest_in_nigerian_culture occupation deletion_reason suspension_reason ban_reason discovery_restriction_note deletion_comment preferred_religion preferred_tribes interests relationship_values dealbreakers languages_spoken preferred_countries relocation_preferences v2_onboarding_answers],
  "exit_attempts" => %w[comment final_comment context], "push_tokens" => %w[last_error],
  "verification_checks" => %w[ai_review_result], "verification_events" => %w[metadata],
  "selfie_verifications" => %w[rejection_reason], "trust_events" => %w[metadata],
  "trust_adjustments" => %w[note], "messages" => %w[body], "reports" => %w[body],
  "daily_introductions" => %w[compatibility_reasons],
  "notifications" => %w[payload], "notification_deliveries" => %w[last_error],
  "community_questions" => %w[body moderation_note aunty_phobie_take risk_flags],
  "community_answers" => %w[body moderation_note risk_flags],
  "community_remarks" => %w[body moderation_note risk_flags],
  "community_events" => %w[description city moderation_note risk_flags],
  "community_stories" => %w[body moderation_note risk_flags],
  "community_reports" => %w[body moderation_note],
  "personas" => %w[current_life family_background looking_for core_values hobbies_and_interests good_stories topics_to_ease_into],
  "dating_hub_batches" => %w[description], "tracked_contact_notes" => %w[body],
  "daily_life_entries" => %w[today_plan highlight learned ask_prompt share_prompt mood focus_tag],
  "audit_logs" => %w[metadata], "aunty_phobie_messages" => %w[content context_snapshot],
  "aunty_phobie_conversations" => %w[escalation_resolution_note],
  "profile_videos" => %w[rejection_reason],
  "career_applications" => %w[cover_letter admin_note], "feedback_items" => %w[message],
  "career_jobs" => %w[summary description responsibilities requirements nice_to_have],
  "error_logs" => %w[message backtrace request_path],
  "company_journal_entries" => %w[title note],
  "company_settings" => %w[mission vision advisor_summary advisor_why advisor_error advisor_focus_areas]
}.freeze

def listed?(map, table, field) = map.fetch(table, []).include?(field)

def sanitizer(table, field)
  return "HASH (sanitizer class PSEUDONYMIZE)" if listed?(PSEUDONYMIZED, table, field)
  return "DESTROY" if listed?(DESTROYED, table, field)
  return "GENERALIZE" if listed?(GENERALIZED, table, field)
  return "REDACT" if listed?(REDACTED, table, field)
  return "QUARANTINE unknowns; preserve allowlisted value" if %w[discovery_restriction_reason deletion_reason_code].include?(field) || (table == "exit_attempts" && %w[reason_code intervention outcome retention_action].include?(field))
  "PRESERVE"
end

def semantics(table, field)
  return "Source row primary key" if field == "id"
  return "Reference to source #{field.delete_suffix('_id').tr('_', ' ')}" if field.end_with?("_id")
  return "Source creation timestamp" if field == "created_at"
  return "Source last-update timestamp" if field == "updated_at"
  return "Source soft-deletion timestamp" if field == "deleted_at"
  return "Public nickname/name shown by Date9ja" if table == "users" && field == "display_name"
  return "Private full-name value used for identity/profile setup" if table == "users" && field == "full_name"
  return "Date9ja login email; confirmation is carried separately" if table == "users" && field == "email"
  return "Date9ja bcrypt password digest" if table == "users" && field == "encrypted_password"
  return "Date9ja phone value; verification is carried separately" if table == "users" && field == "phone"
  return "Flexible V2 onboarding answer object (includes genotype)" if table == "users" && field == "v2_onboarding_answers"
  return "Ordered controlled/free-text list used by profile or matching" if table == "users" && %w[interests languages_spoken relationship_values dealbreakers preferred_countries preferred_religion preferred_tribes relocation_preferences].include?(field)
  return "Date9ja persisted #{field.tr('_', ' ')} state" if field.match?(/status|state|kind|type|reason|category|outcome|visibility|platform|channel|tier|role|action/)
  return "Date9ja persisted #{field.tr('_', ' ')} timestamp" if field.end_with?("_at", "_on")
  return "Date9ja persisted #{field.tr('_', ' ')} count/score/value" if field.match?(/count|score|points|duration|position|amount|age|height|latitude|longitude|distance|number/)
  "Date9ja persisted #{field.tr('_', ' ')} value"
end

def field_contract(table, field, base)
  category, owner, importer, destination = base
  status = case category
  when "media" then table == "active_storage_variant_records" ? "RECONSTRUCTED" : "MEDIA PASS OWNED"
  when "likes/passes", "matches", "conversations", "messages", "blocks", "reports", "discovery", "profile"
    "HISTORICAL GRAPH OWNED"
  when "lifecycle", "safety/moderation", "admin/audit" then "LIFECYCLE OWNED"
  when "analytics/system-only" then "INTENTIONALLY NOT MIGRATED — PROVEN NON-MEMBER/SYSTEM EPHEMERAL"
  when "verification" then "HISTORICAL GRAPH OWNED"
  else "HISTORICAL GRAPH OWNED"
  end

  if table == "users"
    if field == "seed_account"
      importer, destination, status = "ProfileReadinessImport", "Migration::ProfileReadiness + hidden Profile", "MIGRATED"
    elsif field == "profile_completeness_score"
      importer, destination, status = "Profiles::Completion", "Derived D8N completion result", "DERIVED"
    elsif IDENTITY_FIELDS.include?(field)
      importer, destination, status = "IdentityImport", "User/Credential/IdentityIdentifier", "MIGRATED"
    elsif PROFILE_FIELDS.include?(field)
      importer, destination, status = "ProfileReadinessImport", "Profile", "MIGRATED"
    elsif PREFERENCE_FIELDS.include?(field)
      importer, destination, status = "ProfilePreferenceImport / ProfileReadinessImport", "ProfilePreference/Profile/option selection", "MIGRATED"
    elsif SENSITIVE_FIELDS.include?(field) || field == "v2_onboarding_answers"
      importer, destination, status = "SensitiveProfileImport", "Owner-only Profile scalar/option selection", "DESTINATION READY — SOURCE CLASSIFICATION BLOCKED"
    elsif LIFECYCLE_FIELDS.include?(field)
      importer, destination, status = "IdentityImport / ProfileReadinessImport; context importer GAP", "User/BrandMembership/Profile; moderation context GAP", "LIFECYCLE OWNED"
    elsif %w[id created_at updated_at].include?(field)
      importer, destination, status = "IdentityImport", "Migration::ReferenceMap/User timestamps", "MIGRATED"
    end
  end

  visibility = case category
  when /verification|safety|lifecycle|admin/ then "owner + explicitly authorized/audited operator"
  when /messages|blocks|reports/ then "participants/owner; operator only by policy"
  when "media", "profile", "profile/community history" then "source visibility/moderation dependent"
  when "analytics/system-only" then "internal only"
  else "brand-scoped member surface"
  end
  rerun = importer.start_with?("None") ? "not imported" : "idempotent source-id binding required; preserve source timestamps"
  mapping = destination.include?("GAP") || importer.include?("GAP") ? "Explicit owner recorded; implementation gap listed in blocker ledger" : "Explicit column/value mapping; never dynamic attribute copy"
  [ owner, destination, importer, mapping, visibility, sanitizer(table, field), rerun, status ]
end

uri = URI.parse(SOURCE_URL)
connection = PG.connect(dbname: uri.path.delete_prefix("/"), host: uri.host, port: uri.port, user: uri.user, password: uri.password)
columns = connection.exec(<<~SQL).to_a
  SELECT table_name, ordinal_position, column_name, data_type, udt_name,
         is_nullable, column_default
    FROM information_schema.columns
   WHERE table_schema = 'public'
   ORDER BY table_name COLLATE "C", ordinal_position
SQL

missing = columns.map { |row| row.fetch("table_name") }.uniq - TABLES.keys
abort "unclassified source tables: #{missing.join(', ')}" unless missing.empty?

row_counts = TABLES.keys.to_h do |table|
  quoted = connection.quote_ident(table)
  [ table, connection.exec("SELECT count(*) FROM #{quoted}").getvalue(0, 0).to_i ]
end

inventory = TABLES.keys.sort.map do |table|
  base = TABLES.fetch(table)
  count = columns.count { |row| row.fetch("table_name") == table }
  "| `#{table}` | #{base[0]} | #{count} | #{row_counts.fetch(table)} |"
end.join("\n")

matrix = columns.map do |row|
  table = row.fetch("table_name")
  field = row.fetch("column_name")
  type = row.fetch("data_type") == "ARRAY" ? row.fetch("udt_name") : row.fetch("data_type")
  owner, destination, importer, mapping, visibility, treatment, rerun, status = field_contract(table, field, TABLES.fetch(table))
  values = [ "`#{table}`", "`#{field}`", "`#{type}`", semantics(table, field), owner, destination, importer, mapping, visibility, treatment, rerun, status ]
  "| #{values.map { |value| value.to_s.gsub('|', '&#124;').gsub(/\s+/, ' ') }.join(' | ')} |"
end.join("\n")

document = File.read(OUTPUT)
document.sub!(/(?<=<!-- SOURCE-INVENTORY:START -->).*?(?=<!-- SOURCE-INVENTORY:END -->)/m, "\n#{inventory}\n")
document.sub!(/(?<=<!-- FIELD-MATRIX:START -->).*?(?=<!-- FIELD-MATRIX:END -->)/m, "\n#{matrix}\n")
File.write(OUTPUT, document)

warn "generated #{TABLES.length} tables and #{columns.length} field rows"
