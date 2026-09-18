#!/usr/bin/env ruby
# Rails runner; reads a restored baseline snapshot, writes an isolated clone.
require "json"

begin
  connection = Date9ja::Snapshot::Connection.connect!
  source = Date9ja::Snapshot::UserSource.new(connection:)
  counts = Date9ja::Import::ReferenceRepair.call(brand: Brand.find_by!(slug: "date9ja"), source:,
    apply: ENV.fetch("DATE9JA_REFERENCE_REPAIR_APPLY", "false") == "true")
  puts JSON.generate(status: "ok", counts:)
rescue StandardError => error
  warn JSON.generate(status: "failed", error_class: error.class.name)
  exit 1
end
