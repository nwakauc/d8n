#!/usr/bin/env ruby
# Run only against an approved isolated snapshot-A/B staging database.
require "json"

begin
  Date9ja::Snapshot::Connection.assert_runtime_safe!
  bundle = Date9ja::Import::SyncBundle.export(brand: Brand.find_by!(slug: "date9ja"))
  path = ENV.fetch("DATE9JA_SYNC_OUTPUT")
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(JSON.generate(bundle)) }
  puts JSON.generate(status: "ok", rows: bundle.fetch("rows").size)
rescue StandardError => error
  warn JSON.generate(status: "failed", error_class: error.class.name)
  exit 1
end
