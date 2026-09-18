#!/usr/bin/env ruby
# Reviewed ownership manifest required. No bucket listing, overwrite or deletion.
require "aws-sdk-s3"
require "json"
require "active_support/core_ext/object/blank"
require_relative "../../domains/migration/manifest_media_transfer"

if $PROGRAM_NAME == __FILE__
  begin
    manifest = JSON.parse(File.read(ENV.fetch("DATE9JA_MEDIA_MANIFEST")))
    source = Aws::S3::Client.new(region: "auto", force_path_style: true, http_open_timeout: 10, http_read_timeout: 30, retry_limit: 2,
      endpoint: "https://#{ENV.fetch('CLOUDFLARE_ACCOUNT_ID')}.r2.cloudflarestorage.com",
      access_key_id: ENV.fetch("CLOUDFLARE_R2_ACCESS_KEY_ID"), secret_access_key: ENV.fetch("CLOUDFLARE_R2_SECRET_ACCESS_KEY"))
    destination = Aws::S3::Client.new(region: "auto", force_path_style: true, http_open_timeout: 10, http_read_timeout: 30, retry_limit: 2,
      endpoint: ENV.fetch("R2_ENDPOINT"), access_key_id: ENV.fetch("ACCESS_KEY_ID"), secret_access_key: ENV.fetch("SECRET_ACCESS_KEY"))
    result = Migration::ManifestMediaTransfer.new(source:, destination:,
      source_bucket: ENV.fetch("CLOUDFLARE_R2_BUCKET"), destination_bucket: ENV.fetch("STAGING_R2_BUCKET")).call(manifest)
    puts JSON.generate(result)
    exit(result.fetch(:failed).zero? ? 0 : 1)
  rescue StandardError
    warn "Date9ja media transfer aborted: invalid configuration/manifest or required object failure"
    exit 1
  end
end
