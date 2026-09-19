require "rails_helper"

RSpec.describe RescheduleService, type: :service do
  subject(:result) do
    described_class.call(booking: booking, target_trip: target_trip, seat_ids: seat_ids, actor: actor)
  end

  let(:user) { create(:user) }
  let(:actor) { user }
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
  let(:passenger_names) { [ "Ravi Kumar" ] }

  # let!, not let: several examples measure a change in Booking.count or in a cache
  # version, and a lazily created booking would be built inside the expect block
  # and counted as part of the change.
  let!(:booking) do
    hold = SeatHoldService.call(
      user: user, trip: original_trip,
      seat_ids: original_trip.trip_seats.available.order(:id).first(passenger_names.size).map(&:id)
    ).value

    BookingConfirmationService.call(
      user: user, hold: hold,
      passengers: passenger_names.map { |name| { name: name, age: 30, gender: "male" } },
      boarding_stop_id: original_trip.boarding_stops.first.id,
      dropping_stop_id: original_trip.dropping_stops.first.id
    ).value
  end

  let(:seat_ids) { target_trip.trip_seats.available.order(:id).first(passenger_names.size).map(&:id) }

  describe "#call" do
    context "when the move is allowed" do
      it "returns a success" do
        expect(result).to be_success
      end

      it "issues a new booking" do
        expect { result }.to change(Booking, :count).by(1)
      end

      it "links the new booking to the old one" do
        expect(result.value.rescheduled_from).to eq(booking)
      end

      it "puts the new booking on the target trip" do
        expect(result.value.trip).to eq(target_trip)
      end

      it "confirms the new booking" do
        expect(result.value).to be_confirmed
      end

      it "marks the original as rescheduled" do
        result
        expect(booking.reload).to be_rescheduled
      end

      it "frees the original seats" do
        original_seats = booking.trip_seats.to_a
        result
        expect(original_seats.map(&:reload)).to all(be_available)
      end

      it "books the seats on the new trip" do
        expect(result.value.trip_seats.map(&:status)).to all(eq("booked"))
      end

      it "snapshots the new departure time" do
        expect(result.value.departs_at).to eq(target_trip.departs_at)
      end

      it "bumps the cache version for the trip being left" do
        expect { result }
          .to change { AvailabilityCache.version_for(original_trip.origin_city_id, original_trip.destination_city_id, original_trip.service_date) }
          .by(1)
      end

      it "bumps the cache version for the trip being joined" do
        expect { result }
          .to change { AvailabilityCache.version_for(target_trip.origin_city_id, target_trip.destination_city_id, target_trip.service_date) }
          .by(1)
      end
    end

    context "with several passengers" do
      let(:passenger_names) { [ "Ravi Kumar", "Meera Rao" ] }

      it "carries every passenger across" do
        expect(result.value.tickets.map(&:passenger_name)).to match_array(passenger_names)
      end

      it "issues one ticket per passenger" do
        expect(result.value.tickets.count).to eq(2)
      end

      it "leaves the old tickets as history on the freed seats" do
        seat = booking.trip_seats.first
        result
        expect(seat.reload.past_tickets).not_to be_empty
      end
    end

    context "when the new trip stops at the passenger's usual boarding point" do
      let(:shared_point) { booking.boarding_stop.stop_point }

      before do
        create(:boarding_stop, trip: target_trip, stop_point: shared_point,
                               scheduled_at: target_trip.departs_at, position: 5)
      end

      it "keeps that boarding point" do
        expect(result.value.boarding_stop.stop_point).to eq(shared_point)
      end
    end

    context "when the new trip does not stop where the passenger boarded" do
      it "falls back to the trip's first boarding point" do
        expect(result.value.boarding_stop).to eq(target_trip.boarding_stops.first)
      end
    end

    context "when the new trip costs more" do
      let(:target_trip) { trip_on(departs_at: 3.days.from_now, fare: 150_000) }

      it "charges the new fare" do
        expect(result.value.total_paise).to eq(150_000)
      end

      it "records what the passenger owes" do
        expect(result.value.fare_difference_paise).to eq(60_000)
      end
    end

    context "when the target is on a different route" do
      let(:target_trip) { trip_on(departs_at: 2.days.from_now, destination: create(:city)) }

      include_examples "a refused operation", :different_route
      include_examples "an operation that writes nothing", Booking
    end

    context "when the target belongs to a different operator" do
      let(:target_trip) { trip_on(departs_at: 2.days.from_now, operator: create(:operator)) }

      include_examples "a refused operation", :different_operator
      include_examples "an operation that writes nothing", Booking
    end

    context "when the target is the trip they are already on" do
      let(:target_trip) { original_trip }
      let(:seat_ids) { original_trip.trip_seats.available.order(:id).first(1).map(&:id) }

      include_examples "a refused operation", :same_trip
    end

    context "when the target is too close to departure" do
      let(:target_trip) { trip_on(departs_at: 10.minutes.from_now) }

      include_examples "a refused operation", :trip_not_bookable
    end

    context "when the original is inside its own cancellation cutoff" do
      subject(:result) do
        described_class.call(booking: booking, target_trip: target_trip, seat_ids: seat_ids,
                             actor: actor, at: original_trip.departs_at - 30.minutes)
      end

      include_examples "a refused operation", :cutoff_passed
    end

    context "when the original booking has been cancelled" do
      before { CancellationService.call(booking: booking, actor: user) }

      include_examples "a refused operation", :not_confirmed
    end

    context "when the booking belongs to someone else" do
      let(:actor) { create(:user) }

      include_examples "a refused operation", :forbidden
    end

    context "when the wrong number of seats is chosen" do
      let(:passenger_names) { [ "Ravi", "Meera" ] }
      let(:seat_ids) { target_trip.trip_seats.available.order(:id).first(1).map(&:id) }

      include_examples "a refused operation", :seat_count_mismatch

      it "reports how many seats are needed" do
        expect(result.meta[:expected]).to eq(2)
      end
    end

    context "when the chosen seat was taken while the page was open" do
      before { SeatHoldService.call(user: create(:user), trip: target_trip, seat_ids: seat_ids) }

      include_examples "a refused operation", :seats_taken

      it "leaves the original booking confirmed" do
        result
        expect(booking.reload).to be_confirmed
      end

      it "leaves the original seats booked" do
        result
        expect(booking.trip_seats.map(&:reload)).to all(be_booked)
      end

      it "issues no successor" do
        result
        expect(Booking.where(rescheduled_from_id: booking.id)).to be_empty
      end
    end

    context "when the booking has already been rescheduled" do
      before { described_class.call(booking: booking, target_trip: target_trip, seat_ids: seat_ids, actor: actor) }

      let(:seat_ids) { target_trip.trip_seats.available.order(:id).first(1).map(&:id) }

      include_examples "a replayed operation"

      it "creates no second successor" do
        result
        expect(Booking.where(rescheduled_from_id: booking.id).count).to eq(1)
      end
    end

    context "when two reschedules arrive at once", :concurrency do
      self.use_transactional_tests = false

      let!(:target) { booking }
      let!(:chosen_seats) { seat_ids }

      let(:results) do
        booking_id = target.id
        trip_id = target_trip.id
        user_id = user.id
        ids = chosen_seats

        2.times.map do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(booking: Booking.find(booking_id), target_trip: Trip.find(trip_id),
                                   seat_ids: ids, actor: User.find(user_id))
            end
          end
        end.map(&:value)
      end

      it "produces exactly one successor" do
        results
        expect(Booking.where(rescheduled_from_id: target.id).count).to eq(1)
      end

      it "marks the original rescheduled" do
        results
        expect(target.reload).to be_rescheduled
      end
    end
  end
end
