#!/usr/bin/env ruby
# bin/rails runner scripts/date9ja/final_sync.rb
# Protected bundles contain private data. Never put them in git or print them.
require "json"

begin
  Date9ja::Snapshot::Connection.assert_runtime_safe!
  brand = Brand.find_by!(slug: "date9ja")
  baseline = JSON.parse(File.read(ENV.fetch("DATE9JA_SYNC_BASELINE")))
  desired = JSON.parse(File.read(ENV.fetch("DATE9JA_SYNC_DESIRED")))
  counts = Date9ja::Import::FinalSync.call(brand:, baseline:, desired:,
    apply: ENV.fetch("DATE9JA_SYNC_APPLY", "false") == "true")
  puts JSON.generate(status: "ok", counts:)
rescue StandardError => error
  # Exception class only: provider/validation/file errors can contain PII.
  warn JSON.generate(status: "failed", error_class: error.class.name)
  exit 1
end
