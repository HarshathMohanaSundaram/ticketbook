require "rails_helper"

RSpec.describe RescheduleService do
  let(:user) { create(:user) }
  let(:operator) { create(:operator) }
  let(:origin) { create(:city) }
  let(:destination) { create(:city) }

  def trip_on(departs_at:, operator: self.operator, origin: self.origin,
              destination: self.destination, fare: 90_000, seats: 4)
    create(:trip, :with_seats, :with_stops,
           operator: operator, bus: create(:bus, operator: operator),
           origin_city: origin, destination_city: destination,
           departs_at: departs_at, arrives_at: departs_at + 6.hours,
           base_fare_paise: fare, seat_count: seats)
  end

  let(:original_trip) { trip_on(departs_at: 8.hours.from_now) }
  let(:target_trip) { trip_on(departs_at: 2.days.from_now) }

  # A booking made the way the app makes them, so seats and tickets line up.
  def confirmed_booking(trip: original_trip, seats: 1, names: [ "Ravi Kumar" ])
    hold = SeatHoldService.call(user: user, trip: trip,
                                seat_ids: trip.trip_seats.available.order(:id).first(seats).map(&:id)).value
    BookingConfirmationService.call(
      user: user, hold: hold,
      passengers: names.first(seats).map { |n| { name: n, age: 30, gender: "male" } },
      boarding_stop_id: trip.boarding_stops.first.id,
      dropping_stop_id: trip.dropping_stops.first.id
    ).value
  end

  def reschedule(booking, trip: target_trip, seats: nil, actor: user)
    seat_ids = seats || trip.trip_seats.available.order(:id).first(booking.tickets.count).map(&:id)
    described_class.call(booking: booking, target_trip: trip, seat_ids: seat_ids, actor: actor)
  end

  describe "a successful swap" do
    it "issues a new booking linked to the old one" do
      old = confirmed_booking

      result = reschedule(old)

      expect(result).to be_success
      expect(result.value.rescheduled_from).to eq(old)
      expect(result.value.trip).to eq(target_trip)
      expect(result.value).to be_confirmed
    end

    it "marks the original as rescheduled and frees its seats" do
      old = confirmed_booking
      old_seats = old.trip_seats.to_a

      reschedule(old)

      expect(old.reload).to be_rescheduled
      expect(old_seats.map(&:reload).map(&:status)).to all(eq("available"))
      expect(old_seats).to all(be_claimable)
    end

    it "books the seats on the new trip" do
      old = confirmed_booking
      new_booking = reschedule(old).value

      expect(new_booking.trip_seats.map(&:status)).to all(eq("booked"))
      expect(new_booking.trip_seats.map(&:trip_id).uniq).to eq([ target_trip.id ])
    end

    it "carries the passengers across without retyping them" do
      old = confirmed_booking(seats: 2, names: [ "Ravi Kumar", "Meera Rao" ])

      new_booking = reschedule(old).value

      expect(new_booking.tickets.map(&:passenger_name)).to match_array([ "Ravi Kumar", "Meera Rao" ])
      expect(new_booking.tickets.map(&:passenger_age)).to all(eq(30))
    end

    it "keeps the old tickets as history on the freed seats" do
      old = confirmed_booking
      seat = old.trip_seats.first

      reschedule(old)

      expect(seat.reload.current_ticket).to be_nil
      expect(seat.past_tickets.map(&:passenger_name)).to eq([ "Ravi Kumar" ])
    end

    it "keeps the same boarding point when the new trip stops there" do
      old = confirmed_booking
      same_point = old.boarding_stop.stop_point
      create(:boarding_stop, trip: target_trip, stop_point: same_point,
                             scheduled_at: target_trip.departs_at, position: 5)

      new_booking = reschedule(old).value

      expect(new_booking.boarding_stop.stop_point).to eq(same_point)
    end

    it "records the fare difference when the new trip costs more" do
      dearer = trip_on(departs_at: 3.days.from_now, fare: 150_000)
      old = confirmed_booking

      new_booking = reschedule(old, trip: dearer).value

      expect(new_booking.total_paise).to eq(150_000)
      expect(new_booking.fare_difference_paise).to eq(60_000)   # Rs.600 more
    end
  end

  describe "rules" do
    it "refuses a different route" do
      elsewhere = trip_on(departs_at: 2.days.from_now, destination: create(:city))

      expect(reschedule(confirmed_booking, trip: elsewhere).error).to eq(:different_route)
    end

    it "refuses a different operator" do
      rival = trip_on(departs_at: 2.days.from_now, operator: create(:operator))

      expect(reschedule(confirmed_booking, trip: rival).error).to eq(:different_operator)
    end

    it "refuses the same trip" do
      old = confirmed_booking
      expect(reschedule(old, trip: original_trip).error).to eq(:same_trip)
    end

    it "refuses a trip that is not bookable" do
      imminent = trip_on(departs_at: 10.minutes.from_now)

      expect(reschedule(confirmed_booking, trip: imminent).error).to eq(:trip_not_bookable)
    end

    it "refuses inside the one hour cutoff of the original departure" do
      old = confirmed_booking

      travel_to(original_trip.departs_at - 30.minutes) do
        result = reschedule(old)
        expect(result.error).to eq(:cutoff_passed)
      end
    end

    it "refuses a booking that belongs to someone else" do
      expect(reschedule(confirmed_booking, actor: create(:user)).error).to eq(:forbidden)
    end

    it "refuses an already cancelled booking" do
      old = confirmed_booking
      CancellationService.call(booking: old, actor: user)

      expect(reschedule(old.reload).error).to eq(:not_confirmed)
    end

    it "refuses a seat count that does not match the passengers" do
      old = confirmed_booking(seats: 2, names: [ "Ravi", "Meera" ])
      one_seat = target_trip.trip_seats.available.order(:id).first(1).map(&:id)

      result = reschedule(old, seats: one_seat)

      expect(result.error).to eq(:seat_count_mismatch)
      expect(result.meta[:expected]).to eq(2)
    end
  end

  describe "when it refuses, the original booking is untouched" do
    it "leaves everything alone if the new seats were just taken" do
      old = confirmed_booking
      wanted = target_trip.trip_seats.available.order(:id).first
      SeatHoldService.call(user: create(:user), trip: target_trip, seat_ids: [ wanted.id ])

      result = reschedule(old, seats: [ wanted.id ])

      expect(result.error).to eq(:seats_taken)
      expect(old.reload).to be_confirmed
      expect(old.trip_seats.map(&:reload).map(&:status)).to all(eq("booked"))
      expect(Booking.where(rescheduled_from_id: old.id)).to be_empty
    end

    it "leaves everything alone when a rule fails" do
      old = confirmed_booking
      rival = trip_on(departs_at: 2.days.from_now, operator: create(:operator))

      reschedule(old, trip: rival)

      expect(old.reload).to be_confirmed
      expect(old.trip_seats.map(&:reload).map(&:status)).to all(eq("booked"))
    end
  end

  describe "idempotency" do
    it "returns the existing successor instead of rescheduling twice" do
      old = confirmed_booking

      first = reschedule(old)
      second = reschedule(old.reload)

      expect(second).to be_success
      expect(second.meta[:replay]).to be(true)
      expect(second.value.id).to eq(first.value.id)
      expect(Booking.where(rescheduled_from_id: old.id).count).to eq(1)
    end
  end

  describe "concurrency" do
    self.use_transactional_tests = false

    it "produces one successor when two requests arrive together" do
      old = confirmed_booking
      seat_ids = target_trip.trip_seats.available.order(:id).first(1).map(&:id)

      results = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(booking: Booking.find(old.id), target_trip: target_trip,
                                 seat_ids: seat_ids, actor: user)
          end
        end
      end.map(&:value)

      expect(results.count(&:success?)).to be >= 1
      expect(Booking.where(rescheduled_from_id: old.id).count).to eq(1)
      expect(old.reload).to be_rescheduled
    end
  end
end
