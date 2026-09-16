namespace :brands do
  desc "Install DateZA and map DATEZA_API_HOST to it"
  task install_dateza: :environment do
    host = ENV.fetch("DATEZA_API_HOST")
    brand = Brands::DatezaInstaller.call(hosts: [ host ])

    puts "DateZA brand ready: #{brand.slug} -> #{host} (auth: #{brand.auth_methods.join(', ')})"
  end

  desc "Install Date9ja and map DATE9JA_API_HOST to it"
  task install_date9ja: :environment do
    host = ENV.fetch("DATE9JA_API_HOST")
    brand = Brands::Date9jaInstaller.call(hosts: [ host ])

    puts "Date9ja brand ready: #{brand.slug} -> #{host} (auth: #{brand.auth_methods.join(', ')})"
  end

  desc "Ensure Date9ja exists, optionally mapping DATE9JA_API_HOST"
  task ensure_date9ja: :environment do
    hosts = ENV.fetch("DATE9JA_API_HOST", "").split(",").map(&:strip).reject(&:blank?)
    brand = Brands::Provisioner.call(slug: "date9ja", hosts:)
    puts "Date9ja brand ready: #{brand.slug}"
  end

  desc "Verify a provisioned brand's persisted identity and shared capabilities"
  task :verify, [ :slug ] => :environment do |_, args|
    slug = args[:slug].to_s
    brand = Brand.kept.find_by!(slug:)
    contract = D8n::Platform::BrandRegistry.fetch(brand:)
    required = %w[discovery.surface.browse match.eligibility match.relationship.create chat.conversation chat.message.text]
    missing = required.reject { |capability| contract.capability_enabled?(capability) }
    abort "#{slug} brand is missing required capabilities: #{missing.join(', ')}" if missing.any?
    puts "#{brand.name}\nslug: #{brand.slug}\nactive: #{brand.active?}\nrequired contract: present\ndiscovery: #{contract.capability_enabled?("discovery.surface.browse")}\nmatching: #{contract.capability_enabled?("match.eligibility")}\nmessaging: #{contract.capability_enabled?("chat.message.text")}"
  end
end
