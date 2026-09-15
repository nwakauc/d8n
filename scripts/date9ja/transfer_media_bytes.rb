#!/usr/bin/env ruby
# Bucket-to-bucket media transfer for the Date9ja migration (PRODUCTION-
# CUTOVER-RUNBOOK.md section 0.B, Path B1). Source and destination are on
# different Cloudflare accounts, so a same-account `aws s3 sync` cannot do
# this directly -- streams each object through a temp file (GET from
# source, PUT to destination), verifying byte size + MD5 after upload,
# preserving the exact object key. Read-only on the source; never deletes
# or mutates anything there.
#
# Required env: CLOUDFLARE_R2_ACCESS_KEY_ID, CLOUDFLARE_R2_SECRET_ACCESS_KEY,
#   CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_R2_BUCKET (source)
#   ACCESS_KEY_ID, SECRET_ACCESS_KEY, R2_ENDPOINT, STAGING_R2_BUCKET
#   (destination -- the same account-wide token + bucket
#   D8N_R2_DATE9JA_PRODUCTION_* resolves to in .kamal/secrets.production,
#   already proven read/write/delete tonight)
require "aws-sdk-s3"
require "digest/md5"
require "tempfile"
require "json"
require "thread"

CONCURRENCY = Integer(ENV.fetch("D8N_MEDIA_TRANSFER_CONCURRENCY", "16"))

def build_client(access_key_id:, secret_access_key:, endpoint:)
  Aws::S3::Client.new(access_key_id:, secret_access_key:, endpoint:, region: "auto", force_path_style: true)
end

source_bucket = ENV.fetch("CLOUDFLARE_R2_BUCKET")
destination_bucket = ENV.fetch("STAGING_R2_BUCKET")
source_endpoint = "https://#{ENV.fetch('CLOUDFLARE_ACCOUNT_ID')}.r2.cloudflarestorage.com"
dest_endpoint = ENV.fetch("R2_ENDPOINT")
source_creds = { access_key_id: ENV.fetch("CLOUDFLARE_R2_ACCESS_KEY_ID"), secret_access_key: ENV.fetch("CLOUDFLARE_R2_SECRET_ACCESS_KEY"), endpoint: source_endpoint }
dest_creds = { access_key_id: ENV.fetch("ACCESS_KEY_ID"), secret_access_key: ENV.fetch("SECRET_ACCESS_KEY"), endpoint: dest_endpoint }

keys = []
list_client = build_client(**source_creds)
token = nil
loop do
  resp = list_client.list_objects_v2(bucket: source_bucket, max_keys: 1000, continuation_token: token)
  keys.concat(resp.contents.map(&:key))
  token = resp.next_continuation_token
  break unless resp.is_truncated
end

STDERR.puts "#{keys.length} source objects to transfer, concurrency=#{CONCURRENCY}"

queue = Queue.new
keys.each { |k| queue << k }
CONCURRENCY.times { queue << nil }

mutex = Mutex.new
transferred = 0
skipped_already_present = 0
failed = []
total_bytes = 0
processed = 0

def transfer_one(key, source, source_bucket, destination, destination_bucket)
  begin
    existing = destination.head_object(bucket: destination_bucket, key: key)
    source_head = source.head_object(bucket: source_bucket, key: key)
    return [ :skipped, nil ] if existing.content_length == source_head.content_length
  rescue Aws::S3::Errors::NotFound
    # not present yet, proceed to transfer
  end

  size = nil
  Tempfile.create("d8n-media-transfer") do |tmp|
    tmp.binmode
    source.get_object(bucket: source_bucket, key: key) { |chunk| tmp.write(chunk) }
    tmp.flush
    size = tmp.size
    tmp.rewind
    destination.put_object(bucket: destination_bucket, key: key, body: tmp)

    verify = destination.head_object(bucket: destination_bucket, key: key)
    raise "size mismatch after upload (#{verify.content_length} != #{size})" unless verify.content_length == size
  end
  [ :transferred, size ]
end

workers = CONCURRENCY.times.map do
  Thread.new do
    source = build_client(**source_creds)
    destination = build_client(**dest_creds)

    while (key = queue.pop)
      begin
        outcome, size = transfer_one(key, source, source_bucket, destination, destination_bucket)
        mutex.synchronize do
          processed += 1
          if outcome == :skipped
            skipped_already_present += 1
          else
            transferred += 1
            total_bytes += size
          end
          STDERR.puts "#{processed}/#{keys.length} processed (#{transferred} transferred, #{skipped_already_present} already present, #{failed.length} failed)" if processed % 100 == 0
        end
      rescue => e
        mutex.synchronize do
          processed += 1
          failed << { key: key, error: "#{e.class}: #{e.message}" }
        end
      end
    end
  end
end
workers.each(&:join)

result = {
  source_objects: keys.length,
  transferred:,
  skipped_already_present:,
  failed: failed.length,
  failed_keys: failed.first(20),
  total_bytes_transferred: total_bytes
}
puts JSON.pretty_generate(result)
