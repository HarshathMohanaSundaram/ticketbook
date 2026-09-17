# Idempotent seeds: safe to re-run. Builds a week of departures so the search,
# hold and cancellation flows all have something real to work against.
require "securerandom"

TZ = Trip::TZ

puts "Seeding cities..."
CITIES = {
  "bangalore"  => [ "Bangalore", "Karnataka" ],
  "chennai"    => [ "Chennai", "Tamil Nadu" ],
  "hyderabad"  => [ "Hyderabad", "Telangana" ],
  "mysore"     => [ "Mysore", "Karnataka" ],
  "coimbatore" => [ "Coimbatore", "Tamil Nadu" ]
}.freeze

cities = CITIES.to_h do |slug, (name, state)|
  [ slug, City.find_or_create_by!(slug: slug) { |c| c.name = name; c.state = state } ]
end

puts "Seeding operators..."
OPERATORS = {
  "vrl-travels"      => [ "VRL Travels", 4.5 ],
  "srs-travels"      => [ "SRS Travels", 4.1 ],
  "orange-tours"     => [ "Orange Tours", 3.8 ],
  "kpn-travels"      => [ "KPN Travels", 3.2 ]
}.freeze

operators = OPERATORS.to_h do |slug, (name, rating)|
  [ slug, Operator.find_or_create_by!(slug: slug) { |o| o.name = name; o.rating = rating; o.ratings_count = rand(200..4000) } ]
end

puts "Seeding stop points..."
POINTS = {
  "bangalore"  => [ "Madiwala Checkpost", "Anand Rao Circle", "Electronic City Toll" ],
  "chennai"    => [ "Koyambedu CMBT", "Guindy", "Perungalathur" ],
  "hyderabad"  => [ "MGBS", "Ameerpet", "LB Nagar" ],
  "mysore"     => [ "Mysore Bus Stand", "Hebbal Ring Road" ],
  "coimbatore" => [ "Gandhipuram", "Ukkadam" ]
}.freeze

points = POINTS.to_h do |city_slug, names|
  [ city_slug, names.map { |name| StopPoint.find_or_create_by!(city: cities[city_slug], name: name) } ]
end

puts "Seeding buses..."
BUSES = [
  [ "vrl-travels",  "KA01AB1234", "ac",     "sleeper", 36, %w[wifi charging_point blanket water_bottle] ],
  [ "vrl-travels",  "KA01AB5678", "ac",     "seater",  40, %w[wifi charging_point cctv] ],
  [ "srs-travels",  "KA02CD1234", "ac",     "sleeper", 30, %w[charging_point blanket track_my_bus] ],
  [ "srs-travels",  "KA02CD5678", "non_ac", "seater",  44, %w[charging_point reading_light] ],
  [ "orange-tours", "TS03EF1234", "ac",     "sleeper", 36, %w[wifi charging_point blanket cctv track_my_bus] ],
  [ "orange-tours", "TS03EF5678", "non_ac", "sleeper", 30, %w[blanket reading_light] ],
  [ "kpn-travels",  "TN04GH1234", "ac",     "seater",  40, %w[wifi water_bottle cctv] ],
  [ "kpn-travels",  "TN04GH5678", "non_ac", "seater",  44, %w[reading_light] ]
].freeze

buses = BUSES.map do |operator_slug, registration, bus_type, berth_type, seats, amenities|
  Bus.find_or_create_by!(registration_number: registration) do |bus|
    bus.operator = operators[operator_slug]
    bus.bus_type = bus_type
    bus.berth_type = berth_type
    bus.seats_total = seats
    bus.amenity_codes = amenities
  end
end

# Sleeper buses are numbered by deck (L1.., U1..), seaters by row and column.
def seat_numbers_for(bus)
  if bus.sleeper?
    per_deck = bus.seats_total / 2
    (1..per_deck).map { |n| "L#{n}" } + (1..per_deck).map { |n| "U#{n}" }
  else
    rows = (bus.seats_total / 4.0).ceil
    (1..rows).flat_map { |row| %w[A B C D].map { |col| "#{row}#{col}" } }.first(bus.seats_total)
  end
end

puts "Seeding drivers..."
DRIVER_NAMES = [
  "Ramesh Kumar", "Suresh Babu", "Manjunath Gowda", "Prakash Reddy",
  "Vinod Sharma", "Anil Nair", "Sathish Kumar", "Ravi Shankar",
  "Mahesh Patil", "Girish Rao", "Naveen Chandra", "Karthik Raja"
].freeze

drivers = operators.values.flat_map.with_index do |operator, operator_index|
  DRIVER_NAMES.each_slice(3).to_a[operator_index].map.with_index do |driver_name, index|
    Driver.find_or_create_by!(licence_number: "KA#{operator_index}#{index}#{rand(10_000..99_999)}") do |driver|
      driver.operator = operator
      driver.name = driver_name
      driver.phone = "9#{rand(100_000_000..999_999_999)}"
      driver.licence_expires_on = Date.current + rand(200..900).days
    end
  end
end

drivers_by_operator = drivers.group_by(&:operator_id)

puts "Seeding trips, seats and stops..."
# origin, destination, journey minutes, departure hours (IST), base fare in paise
ROUTES = [
  [ "bangalore", "chennai",    6 * 60,  [ 6, 14, 21, 23 ], 90_000 ],
  [ "chennai", "bangalore",    6 * 60,  [ 7, 15, 22 ],     90_000 ],
  [ "bangalore", "hyderabad",  9 * 60,  [ 8, 20, 22 ],     130_000 ],
  [ "hyderabad", "bangalore",  9 * 60,  [ 9, 19, 21 ],     130_000 ],
  [ "bangalore", "mysore",     3 * 60,  [ 7, 11, 16, 19 ], 45_000 ],
  [ "bangalore", "coimbatore", 8 * 60,  [ 10, 21, 23 ],    110_000 ]
].freeze

# What a class of bus costs relative to the route's base fare. Without this every
# bus on a route is priced identically and the fare filter looks broken.
FARE_MULTIPLIER = {
  [ "ac", "sleeper" ] => 1.25,
  [ "ac", "seater" ] => 1.0,
  [ "non_ac", "sleeper" ] => 0.9,
  [ "non_ac", "seater" ] => 0.72
}.freeze

# A bus cannot be on two trips at once, so pick the first one that is free for
# the whole window. Without this the seeded schedule looks plausible until a
# reviewer notices KA01AB1234 leaving two cities simultaneously.
def bus_free_at(buses, offset, departs_at, arrives_at)
  buses.size.times do |i|
    bus = buses[(offset + i) % buses.size]
    clash = Trip.where(bus: bus)
                .where("departs_at < ? AND arrives_at > ?", arrives_at, departs_at)
                .exists?
    return bus unless clash
  end
  nil
end

created = 0
(0..6).each do |day_offset|
  date = Date.current.in_time_zone(TZ) + day_offset.days

  ROUTES.each_with_index do |(origin, destination, minutes, hours, fare), route_index|
    hours.each_with_index do |hour, slot|
      departs_at = date.change(hour: hour, min: [ 0, 15, 30, 45 ].sample)
      arrives_at = departs_at + minutes.minutes

      bus = bus_free_at(buses, day_offset + route_index + slot, departs_at, arrives_at)
      next if bus.nil?

      trip = Trip.find_or_initialize_by(bus: bus, departs_at: departs_at)
      next if trip.persisted?

      trip_fare = (fare * FARE_MULTIPLIER.fetch([ bus.bus_type, bus.berth_type ])).to_i

      # A relief driver is rostered on anything over six hours.
      crew = drivers_by_operator[bus.operator_id].sample(2)

      trip.assign_attributes(
        operator: bus.operator,
        driver: crew.first,
        relief_driver: (crew.second if minutes > 360),
        origin_city: cities[origin],
        destination_city: cities[destination],
        arrives_at: arrives_at,
        base_fare_paise: trip_fare,
        status: "scheduled",
        seats_total: bus.seats_total
      )
      trip.save!
      created += 1

      now = Time.current
      TripSeat.insert_all!(
        seat_numbers_for(bus).map do |number|
          {
            trip_id: trip.id, seat_number: number, status: "available",
            berth_type: bus.berth_type,
            # Lower berths carry a small premium, as they do in the real world.
            price_paise: number.start_with?("L") ? (trip_fare * 1.1).to_i : trip_fare,
            created_at: now, updated_at: now
          }
        end
      )

      points[origin].each_with_index do |point, position|
        BoardingStop.create!(trip: trip, stop_point: point,
                             scheduled_at: departs_at + (position * 20).minutes, position: position)
      end
      points[destination].each_with_index do |point, position|
        DroppingStop.create!(trip: trip, stop_point: point,
                             scheduled_at: arrives_at + (position * 20).minutes, position: position)
      end
    end
  end
end

puts "Seeding a demo passenger..."
User.find_or_create_by!(email: "passenger@example.com") { |u| u.name = "Demo Passenger" }

puts <<~SUMMARY
  Done.
    cities:          #{City.count}
    operators:       #{Operator.count}
    buses:           #{Bus.count}
    stop points:     #{StopPoint.count}
    drivers:         #{Driver.count}
    trips:           #{Trip.count} (#{created} new)
    trip seats:      #{TripSeat.count}
    trip stops:      #{TripStop.count}
    login with:      passenger@example.com
SUMMARY
