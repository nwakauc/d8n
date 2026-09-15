require Rails.root.join("lib/d8n/date9ja_production_configuration")

if Rails.env.production? && ENV["D8N_DEPLOYMENT_ENV"] == "production"
  Rails.application.config.after_initialize do
    D8n::Date9jaProductionConfiguration.validate!(
      storage_service_checker: ->(name) { ActiveStorage::Blob.services.fetch(name) }
    )
  end
end
