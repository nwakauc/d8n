# frozen_string_literal: true

namespace :date9ja do
  desc "Rehearsal: Date9ja identity import against a restored scratch snapshot " \
       "(set DATE9JA_SNAPSHOT_DATABASE_URL). Prints a PII-free reconciliation JSON."
  task import_identity: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::UserSource.new(connection: connection)

    result = Date9ja::Import::IdentityImport.call(brand: brand, source: source)

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end

  desc "Rehearsal: Date9ja profile-photo MEDIA PREFLIGHT (pass 1) against a restored scratch " \
       "snapshot (set DATE9JA_SNAPSHOT_DATABASE_URL). No byte transfer, no ProfilePhoto. " \
       "Prints a PII-free reconciliation JSON."
  task preflight_photos: :environment do
    require "json"

    brand = Brand.kept.find_by!(slug: "date9ja")

    connection = Date9ja::Snapshot::Connection.connect!
    source = Date9ja::Snapshot::PhotoSource.new(connection: connection)

    result = Date9ja::Import::PhotoImport.call(brand: brand, source: source)

    puts JSON.pretty_generate(result.reconciliation.to_h)
  ensure
    Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
  end
end
