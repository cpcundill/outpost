require 'csv'

start_time = Time.now

# Seed users from old DB
users_file = File.open('lib/seeds/users.csv', "r:ISO-8859-1")
open_objects_users_csv = CSV.parse(users_file, headers: true)

csv_file = File.open('lib/seeds/bucksfis geo.csv', "r:ISO-8859-1")
bucks_csv = CSV.parse(csv_file, headers: true)

bucks_csv.each do |row| # CREATE ORGS BASED ON TYPE
  if row['service_type'] == 'Organisation'
    organisation = Organisation.new
    organisation.name = row['title']
    organisation.description = ActionView::Base.full_sanitizer.sanitize(row['description'])
    organisation.email = row['contact_email']
    organisation.url = row['website']
    organisation.old_external_id = row['externalid']
    unless organisation.save
      puts "Organisation #{organisation.name} failed to save"
    end
  end
end

Rake::Task['taxonomy:create_categories_from_old_db'].invoke
Rake::Task['ofsted:create_initial_items'].invoke
Rake::Task['ofsted:set_open_objects_external_ids'].invoke

bucks_csv.each.with_index do |row, line|
  next unless (line % 6 == 0)
  puts "Processing line (service build): #{line} of #{bucks_csv.size}"

  open_objects_users = open_objects_users_csv.select{ |user_row| user_row['externalId'] == row['record_editor'] } # users from open objects csv
  outpost_users = User.where(old_external_id: row['record_editor']) # new database users already created by this seed

# FIND OR CREATE ORG

  organisation = Organisation.where(old_external_id: row['parent_organisation']).first unless row['parent_organisation'].nil? # find from parent ID
  organisation ||= outpost_users.first&.organisation # find from user
  organisation ||= Organisation.where(old_external_id: row['externalid']).first # if for service that is also org

  if organisation.blank?
    organisation = Organisation.new
    unless organisation.save
      puts "Organisation #{organisation.name} failed to save"
    end
  end

# CREATE USER IF DOESN'T ALREADY EXIST AND DID PREVIOUSLY
  if outpost_users.blank? & open_objects_users.any?
    open_objects_user = open_objects_users.first
    password = "A9b#{SecureRandom.hex(8)}1yZ"
    user = User.new
    user.email = open_objects_user['email']
    user.old_external_id = open_objects_user['externalId']
    user.first_name = open_objects_user['firstName']
    user.last_name = open_objects_user['lastName']
    user.organisation_id = organisation.id
    user.password = password
    unless user.save
      puts "User #{user.email} failed to save"
    end
  end

# CREATE SERVICE

  service ||= Service.new

  if (row['ecd_opt_out_website'] == "Hide completely from public website") || (row['ecd_opt_out_website'] == "Admin access only, never on website")
    service.visible = false
  end

  if row['service_type'] == 'Childcare'
    if row['registered_setting_identifier'].present?
      ofsted_item = OfstedItem.where(open_objects_external_id: row['registered_setting_identifier']).first
      service.ofsted_item_id = ofsted_item.id if ofsted_item
    end
  end

  service.name = row['title']
  service.description = ActionView::Base.full_sanitizer.sanitize(row['description'])
  service.url = row['website']

  service.organisation = organisation

  service.snapshot_action = "import"

  if row['venue_name'].present? && (Location.where('lower(name) = ?', row['venue_name'].downcase).size > 0) # Assign location if already exists
    service.locations << Location.where('lower(name) = ?', row['venue_name'].downcase).first
  else # Otherwise create a new one
    location = Location.new

    if row['ecd_opt_out_website'] == "Hide street level location and don't show on maps"
      location.visible = false
    elsif row['ecd_opt_out_website'] == "Hide street level location but show on maps"
      location.mask_exact_address = true
    end

    location.name = row['venue_name']
    location.address_1 = [row['venue_address_1'], row['venue_address_2']].join(' ')
    location.city = row['venue_address_4']
    location.state_province = 'Buckinghamshire'
    location.postal_code = row['venue_postcode']
    location.latitude = row['latitude']
    location.longitude = row['longitude']
    location.country = 'GB'

    # add accessibility info to locations
    unless row['venue_facilities'] == nil
      options = row['venue_facilities'].split("\n")
      # remove unwanted values
      options = options - ["Accessible Website", "Cooking"]
      options.each do |option|
        location.accessibilities << Accessibility.find_or_initialize_by({name: option.downcase.capitalize})
      end
    end

    location.skip_postcode_validation = true
    unless location.save
      puts "Location #{location.name} failed to save"
    end
    service.locations << location
  end

  unless row['attributes'] == nil
    attributes = row['attributes'].split("\n")
    attributes.each do |attribute|
      cost_taxonomy_path = ["Cost", attribute]
      taxonomy = Taxonomy.find_or_create_by_path(cost_taxonomy_path)
      service.taxonomies |= [taxonomy]
    end
  end

  unless row['coronavirus_status'] == nil
    coronavirus_statuses = row['coronavirus_status'].split("\n")
    coronavirus_statuses.each do |coronavirus_status|
      coronavirus_status_path = ["Coronavirus status", coronavirus_status]
      taxonomy = Taxonomy.find_or_create_by_path(coronavirus_status_path)
      service.taxonomies |= [taxonomy]
    end
  end

  unless row['lo_age_bands'] == nil
    age_groups = row['lo_age_bands'].split("\n")

    min_age = age_groups.map {|x| x.scan(/\d+/)}.flatten.map(&:to_i).min
    max_age = age_groups.map {|x| x.scan(/\d+/)}.flatten.map(&:to_i).max

    max_age = nil if age_groups.include? "25 plus"

    if age_groups.include? "All ages"
      min_age = nil
      max_age = nil
    end

    service.min_age = min_age
    service.max_age = max_age
  end

  unless row['lo_needs_level'] == nil
    send_needs = row['lo_needs_level'].split("\n")
    send_needs.each do |send_need|
      send_need_taxonomy_path = ["SEND needs", send_need]
      taxonomy = Taxonomy.find_or_create_by_path(send_need_taxonomy_path)
      service.taxonomies |= [taxonomy]
    end
    if send_needs.include? "All Needs Met"
      service.taxonomies |= Taxonomy.find_by_path("SEND needs").children
    end
  end

  unless row['familychannel'] == nil
    lines = row['familychannel'].split("\n")
    lines.each do |line|
      categories = line.split(' > ')
      categories.delete("Family Information")

      taxonomy = Taxonomy.find_or_create_by_path(categories.unshift("Categories"))
      service.taxonomies |= [taxonomy]
    end
  end

  unless row['parentchannel'] == nil
    lines = row['parentchannel'].split("\n")
    lines.each do |line|
      categories = line.split(' > ')
      taxonomy = Taxonomy.find_or_create_by_path(categories.unshift("Categories"))
      service.taxonomies |= [taxonomy]
    end
  end

  unless row['youthchannel'] == nil
    lines = row['youthchannel'].split("\n")
    lines.each do |line|
      categories = line.split(' > ')
      taxonomy = Taxonomy.find_or_create_by_path(categories.unshift("Categories"))
      service.taxonomies |= [taxonomy]
    end
  end

  unless row['childrenscentrechannel'] == nil
    lines = row['childrenscentrechannel'].split("\n")
    lines.each do |line|
      categories = line.split(' > ')
      taxonomy = Taxonomy.find_or_create_by_path(categories.unshift("Categories"))
      service.taxonomies |= [taxonomy]
    end
  end

  service.skip_mongo_callbacks = true

  service.locations.each {|l| l.skip_postcode_validation = true }
  unless service.save
    puts "Service #{service.name} failed to save"
  end

  if (row['contact_name'].present? || row['contact_telephone'].present? || row['contact_email'].present?) # contact just needs one of these ethings to save
    contact = Contact.new
    contact.service_id = service.id
    contact.name = row['contact_name']
    contact.title = row['contact_position']
    contact.email = row['contact_email']

    # If more than one number, add first to contact with name, email and position, and create blank contacts for remaining numbers
    if row['contact_telephone'].present?
      if row['contact_telephone']&.include? "\n"
        numbers = row['contact_telephone'].split("\n")
        contact.phone = numbers.first

        unless contact.save
          puts "Contact #{contact.name} failed to save"
          byebug
        end

        numbers = numbers.drop(1) # now create contacts for remaining numbers
        numbers.each do |number|
          contact = Contact.new
          contact.phone = number
          contact.service_id = service.id
          unless contact.save
            puts "Phone #{number} failed to save"
            byebug
          end
        end
      end
    end
  end

end

#Create bucks and fg users
user_logins_yaml = Rails.root.join('lib', 'seeds', 'user_logins.yml')
user_logins = YAML::load_file(user_logins_yaml)
user_logins.each do |user_login|
  user_login["admin_users"] = true
  user_login["admin_ofsted"] = true
  User.create!(user_login) unless (User.where(email: user_login["email"]).size > 0)
end

end_time = Time.now

Rake::Task['taxonomy:map_to_new_taxonomy'].invoke
Rake::Task['taxonomy:delete_old_taxonomies'].invoke

all_needs_met_taxonomy = Taxonomy.where(name: "All Needs Met").first
all_needs_met_taxonomy.destroy!

puts "Took #{(end_time - start_time)/60} minutes"

# lock top-level taxa
Taxonomy.roots.each do |t|
  t.locked = true
  t.save
end