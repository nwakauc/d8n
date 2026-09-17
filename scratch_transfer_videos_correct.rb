require "json"

$stdout.sync = true
$stderr.sync = true

# Same fix as scratch_transfer_photos_correct.rb: Media::StorageResolver
# reads these Rails.configuration.x.* values, which are normally only set
# from ENV inside config/environments/production.rb -- which never loads
# under RAILS_ENV=test (required by Date9ja::Snapshot::Connection.
# assert_runtime_safe!). Setting them directly here, for this run only,
# replicates exactly what that file would have set with
# D8N_R2_ENABLED=true D8N_DEPLOYMENT_ENV=production D8N_R2_BRANDS=date9ja.
Rails.configuration.x.r2_storage_enabled = true
Rails.configuration.x.media_storage_environment = "production"
Rails.configuration.x.r2_brand_slugs = [ "date9ja" ]

brand = Brand.kept.find_by!(slug: "date9ja")
service = ActiveStorage::Blob.services.fetch(:r2_date9ja_production)

resolved = Media::StorageResolver.service_name(brand: brand)
raise "StorageResolver did not resolve to r2_date9ja_production (got #{resolved.inspect})" unless resolved == "r2_date9ja_production"
puts "StorageResolver confirmed: #{resolved}"

# service.client.client (Active Storage's own configured Aws::S3::Client) has
# no explicit read/open timeout, which let a real run hang indefinitely on a
# stalled TCP connection (confirmed via `nettop`: 410k retransmits, 2+ hours
# with zero progress, connection never torn down). Build a dedicated client
# with the same bounded timeouts scripts/date9ja/transfer_media_bytes.rb
# already proved safe for large real R2 transfers, so a stalled connection
# fails fast and the run can be retried instead of hanging forever.
require "aws-sdk-s3"
bounded_client = Aws::S3::Client.new(
  access_key_id: ENV.fetch("D8N_R2_DATE9JA_PRODUCTION_ACCESS_KEY_ID"),
  secret_access_key: ENV.fetch("D8N_R2_DATE9JA_PRODUCTION_SECRET_ACCESS_KEY"),
  endpoint: ENV.fetch("D8N_R2_ENDPOINT"),
  region: "auto", force_path_style: true,
  http_open_timeout: 15, http_read_timeout: 60, retry_limit: 3
)

# Thin visibility wrapper -- VideoTransfer has no per-record progress hook,
# and this run has been hard to distinguish "grinding through many slow/
# failing videos" from "stuck on one" using network stats alone. Logs a
# PII-free key-length + byte-size line per head/download call, nothing else.
class LoggingReader
  def initialize(inner) = @inner = inner

  def head(key)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @inner.head(key)
    STDERR.puts "[video-transfer] head key_len=#{key.to_s.length} bytes=#{result&.dig(:byte_size)} took=#{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(1)}s"
    result
  end

  def download(key, io:, byte_ceiling:, chunk_size: 5 * 1024 * 1024)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    STDERR.puts "[video-transfer] download start key_len=#{key.to_s.length}"
    written = @inner.download(key, io:, byte_ceiling:, chunk_size:)
    STDERR.puts "[video-transfer] download done bytes=#{written} took=#{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(1)}s"
    written
  rescue => e
    STDERR.puts "[video-transfer] download FAILED after #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(1)}s: #{e.class}"
    raise
  end
end

connection = Date9ja::Snapshot::Connection.connect!
begin
  source = Date9ja::Snapshot::VideoSource.new(connection: connection)
  locator = Date9ja::Snapshot::VideoLocatorSource.new(connection: connection)
  reader = LoggingReader.new(Date9ja::Storage::DestinationBucketReader.new(client: bounded_client, bucket: service.bucket.name))

  result = Date9ja::Import::VideoTransfer.call(
    brand:, source:, locator:, source_reader: reader, stage: :domain, processing: :inline
  )
  puts JSON.pretty_generate(result.reconciliation.to_h)
ensure
  Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
end
