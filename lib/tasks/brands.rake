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
end
