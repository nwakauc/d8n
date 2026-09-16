require "json"

# Media::StorageResolver.service_name reads these Rails.configuration.x.*
# values, which are normally only set from ENV inside config/environments/
# production.rb -- which never loads under RAILS_ENV=test (required by
# Date9ja::Snapshot::Connection.assert_runtime_safe!). Setting them directly
# here, for this run only, replicates exactly what that file would have set
# with D8N_R2_ENABLED=true D8N_DEPLOYMENT_ENV=production D8N_R2_BRANDS=date9ja.
Rails.configuration.x.r2_storage_enabled = true
Rails.configuration.x.media_storage_environment = "production"
Rails.configuration.x.r2_brand_slugs = [ "date9ja" ]

brand = Brand.kept.find_by!(slug: "date9ja")
service = ActiveStorage::Blob.services.fetch(:r2_date9ja_production)

resolved = Media::StorageResolver.service_name(brand: brand)
raise "StorageResolver did not resolve to r2_date9ja_production (got #{resolved.inspect})" unless resolved == "r2_date9ja_production"
puts "StorageResolver confirmed: #{resolved}"

connection = Date9ja::Snapshot::Connection.connect!
begin
  source = Date9ja::Snapshot::PhotoSource.new(connection: connection)
  locator = Date9ja::Snapshot::MediaLocatorSource.new(connection: connection)
  reader = Date9ja::Storage::DestinationBucketReader.new(client: service.client.client, bucket: service.bucket.name)

  result = Date9ja::Import::PhotoTransfer.call(
    brand:, source:, locator:, source_reader: reader, processing: :inline
  )
  puts JSON.pretty_generate(result.reconciliation.to_h)
ensure
  Date9ja::Snapshot::Connection.remove_connection if Date9ja::Snapshot::Connection.connected?
end
