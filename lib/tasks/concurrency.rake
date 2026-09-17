# Proves the no-oversell guarantee against a real database with real threads.
#
#   bin/rails concurrency:check
#   bin/rails "concurrency:check[14]"    # more racers (must stay under the pool)
#
# Not a substitute for the specs -- it is the demo you can run in front of someone
# and watch Postgres refuse to sell a seat twice.
namespace :concurrency do
  desc "Race N users for one seat and show that exactly one wins"
  task :check, [ :racers ] => :environment do |_t, args|
    abort "Refusing to run outside development or test." unless Rails.env.local?

    racers = (args[:racers] || 12).to_i
    pool = ActiveRecord::Base.connection_pool.size
    abort "Connection pool is #{pool}; use at most #{pool - 1} racers." if racers >= pool

    trip = Trip.bookable.first or abort "No bookable trip. Run bin/rails db:seed."
    users = racers.times.map { |i| User.find_or_create_by!(email: "racer#{i}@example.test") }

    reset = lambda do
      TripSeat.where(trip: trip).update_all(status: "available", hold_id: nil, hold_expires_at: nil)
      Hold.where(trip: trip).delete_all
    end

    puts "\nTrip #{trip.id}: #{trip.operator_name}, departs #{trip.departs_at.in_time_zone(Trip::TZ).strftime('%-d %b %-I:%M %p')}"
    puts "Connection pool: #{pool}\n\n"

    # ---------------------------------------------------------------
    reset.call
    seat = trip.trip_seats.numbered.first
    puts "TEST 1  #{racers} users, all fighting for seat #{seat.seat_number}"

    started = Time.current
    results = users.map do |user|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          SeatHoldService.call(user: user, trip: trip, seat_ids: [ seat.id ])
        end
      end
    end.map(&:value)
    elapsed = ((Time.current - started) * 1000).round

    winners = results.count(&:success?)
    puts "        winners: #{winners}   rejected: #{results.count(&:failure?)}   (#{elapsed}ms)"
    puts "        reasons: #{results.select(&:failure?).map(&:error).tally}"
    puts "        holds in database: #{Hold.where(trip: trip).count}"
    puts "        #{winners == 1 && Hold.where(trip: trip).count == 1 ? 'PASS -- the seat was sold exactly once' : 'FAIL'}\n\n"

    # ---------------------------------------------------------------
    reset.call
    a, b, c = trip.trip_seats.numbered.first(3)
    puts "TEST 2  overlapping pairs -- the classic deadlock shape"
    pairs = [ [ a, b ], [ b, a ], [ b, c ], [ c, b ] ]
    results = pairs.each_with_index.map do |(x, y), i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          SeatHoldService.call(user: users[i], trip: trip, seat_ids: [ x.id, y.id ])
        end
      end
    end.map(&:value)

    deadlocked = results.count { |r| r.failure? && r.error == :deadlock }
    puts "        winners: #{results.count(&:success?)}   rejected: #{results.count(&:failure?)}   deadlocks: #{deadlocked}"
    puts "        #{deadlocked.zero? ? 'PASS -- ORDER BY id kept them in a queue' : 'FAIL -- deadlock detected'}\n\n"

    # ---------------------------------------------------------------
    reset.call
    puts "TEST 3  expiry without any background job"
    hold = SeatHoldService.call(user: users[0], trip: trip, seat_ids: [ a.id ]).value
    Hold.where(id: hold.id).update_all(created_at: 10.minutes.ago, expires_at: 1.second.ago)
    TripSeat.where(hold_id: hold.id).update_all(hold_expires_at: 1.second.ago)
    a.reload
    taken = SeatHoldService.call(user: users[1], trip: trip, seat_ids: [ a.id ])
    puts "        seat reads '#{a.status}' in the database, but claimable? is #{a.claimable?}"
    puts "        #{taken.success? ? 'PASS -- a dead Sidekiq cannot wedge a seat' : 'FAIL'}\n\n"

    # ---------------------------------------------------------------
    reset.call
    puts "TEST 4  a failed pick must not destroy the hold you already have"
    mine = SeatHoldService.call(user: users[0], trip: trip, seat_ids: [ a.id, b.id ]).value
    SeatHoldService.call(user: users[1], trip: trip, seat_ids: [ c.id ])
    failed = SeatHoldService.call(user: users[0], trip: trip, seat_ids: [ b.id, c.id ])
    puts "        second pick rejected with: #{failed.error}"
    puts "        original hold is still: #{mine.reload.status}"
    puts "        #{mine.active? ? 'PASS -- validated before anything was written' : 'FAIL -- early return committed a partial change'}\n\n"

    # ---------------------------------------------------------------
    reset.call
    puts "TEST 5  swapping to an overlapping set of seats"
    SeatHoldService.call(user: users[0], trip: trip, seat_ids: [ a.id, b.id ])
    swap = SeatHoldService.call(user: users[0], trip: trip, seat_ids: [ b.id, c.id ])
    ok = swap.success? && a.reload.available? && b.reload.held? && c.reload.held? &&
         users[0].holds.live.count == 1
    puts "        {#{a.seat_number},#{b.seat_number}} -> {#{b.seat_number},#{c.seat_number}}: #{swap.success? ? 'success' : swap.error}"
    puts "        #{a.seat_number} released, #{b.seat_number} kept, one live hold: #{ok}"
    puts "        #{ok ? 'PASS' : 'FAIL'}\n\n"

    reset.call
    User.where(email: users.map(&:email)).delete_all
    puts "Cleaned up.\n\n"
  end
end
