#!/usr/bin/env ruby
# Explicit protected plan, isolated clone only. No cross-brand account linking.
require "json"

begin
  source = Date9ja::Snapshot::UserSource.new(connection: Date9ja::Snapshot::Connection.connect!)
  brand = Brand.find_by!(slug: "date9ja")
  if ENV.fetch("DATE9JA_PHONE_IDENTITY_REPAIR_APPLY", "false") == "true"
    expected = JSON.parse(File.read(ENV.fetch("DATE9JA_PHONE_IDENTITY_PLAN")))
    counts = Date9ja::Import::PhoneIdentityRepair.apply!(brand:, source:, expected_plan: expected)
    puts JSON.generate(status: "ok", counts:)
  else
    plan = Date9ja::Import::PhoneIdentityRepair.plan(brand:, source:)
    File.open(ENV.fetch("DATE9JA_PHONE_IDENTITY_PLAN_OUTPUT"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.generate(plan))
    end
    puts JSON.generate(status: "preview", phone_identities_missing: plan.size)
  end
rescue StandardError => error
  warn JSON.generate(status: "failed", error_class: error.class.name)
  exit 1
end
