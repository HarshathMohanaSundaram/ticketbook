require "rails_helper"

RSpec.describe BookingConfirmationService, type: :service do
  subject(:result) do
    described_class.call(user: user, hold: hold, passengers: passengers,
                         boarding_stop_id: boarding_stop_id, dropping_stop_id: dropping_stop_id)
  end

  let(:user) { create(:user) }
  let(:trip) { create(:trip, :with_seats, :with_stops, seat_count: 4, departs_at: 8.hours.from_now) }
  let(:seat_count) { 1 }
  let(:hold) do
    SeatHoldService.call(user: user, trip: trip,
                         seat_ids: trip.trip_seats.available.order(:id).first(seat_count).map(&:id)).value
  end
  let(:passengers) { Array.new(seat_count) { |i| { name: "Passenger #{i + 1}", age: 30 + i, gender: "male" } } }
  let(:boarding_stop_id) { trip.boarding_stops.first.id }
  let(:dropping_stop_id) { trip.dropping_stops.first.id }

  describe "#call" do
    context "when the hold is live and the details are complete" do
      let(:seat_count) { 2 }

      it "returns a success" do
        expect(result).to be_success
      end

      it "creates one booking" do
        expect { result }.to change(Booking, :count).by(1)
      end

      it "issues a ticket for every seat" do
        expect(result.value.tickets.count).to eq(2)
      end

      it "names each passenger on their ticket" do
        expect(result.value.tickets.order(:id).map(&:passenger_name))
          .to eq([ "Passenger 1", "Passenger 2" ])
      end

      it "books every seat" do
        expect(result.value.trip_seats.map(&:status)).to all(eq("booked"))
      end

      it "detaches the seats from the hold" do
        expect(result.value.trip_seats.map(&:hold_id)).to all(be_nil)
      end

      it "marks the hold as converted" do
        result
        expect(hold.reload).to be_converted
      end

      it "charges the sum of the seat prices" do
        # Read off the booking, not the hold: confirmation detaches the seats from
        # the hold, so hold.trip_seats is empty by now.
        expect(result.value.total_paise).to eq(result.value.trip_seats.sum(&:price_paise))
      end

      it "charges what the hold quoted" do
        quoted = hold.total_paise
        expect(result.value.total_paise).to eq(quoted)
      end

      it "snapshots the departure time" do
        expect(result.value.departs_at).to eq(trip.departs_at)
      end

      it "records the boarding point" do
        expect(result.value.boarding_stop_id).to eq(boarding_stop_id)
      end

      it "generates a PNR" do
        expect(result.value.pnr).to match(/\A[A-Z0-9]{8}\z/)
      end

      it "bumps the corridor's cache version" do
        expect { result }
          .to change { AvailabilityCache.version_for(trip.origin_city_id, trip.destination_city_id, trip.service_date) }
          .by(1)
      end
    end

    # The idempotency requirement from the brief: refreshing must not produce a
    # second booking.
    context "when the same confirmation is submitted again" do
      before { described_class.call(user: user, hold: hold, passengers: passengers,
                                    boarding_stop_id: boarding_stop_id, dropping_stop_id: dropping_stop_id) }

      include_examples "a replayed operation"

      it "creates no second booking" do
        expect { result }.not_to change(Booking, :count)
      end

      it "returns the booking that already exists" do
        expect(result.value).to eq(Booking.find_by(hold_id: hold.id))
      end

      it "issues no extra tickets" do
        expect { result }.not_to change(Ticket, :count)
      end
    end

    context "when the confirmation is submitted five times" do
      let(:results) do
        5.times.map do
          described_class.call(user: user, hold: hold, passengers: passengers,
                               boarding_stop_id: boarding_stop_id, dropping_stop_id: dropping_stop_id)
        end
      end

      it "succeeds every time" do
        expect(results).to all(be_success)
      end

      it "returns the same booking every time" do
        expect(results.map { |r| r.value.id }.uniq.size).to eq(1)
      end

      it "leaves exactly one booking in the database" do
        results
        expect(Booking.where(hold_id: hold.id).count).to eq(1)
      end
    end

    context "when several confirmations arrive at once", :concurrency do
      # Threads need committed rows and their own connections.
      self.use_transactional_tests = false

      let!(:live_hold) { hold }

      let(:results) do
        hold_id = live_hold.id
        user_id = user.id
        passenger_list = passengers
        stops = { boarding_stop_id: boarding_stop_id, dropping_stop_id: dropping_stop_id }

        8.times.map do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(user: User.find(user_id), hold: Hold.find(hold_id),
                                   passengers: passenger_list, **stops)
            end
          end
        end.map(&:value)
      end

      it "succeeds for every request" do
        expect(results).to all(be_success)
      end

      it "returns one distinct booking" do
        expect(results.map { |r| r.value.id }.uniq.size).to eq(1)
      end

      it "creates exactly one booking" do
        results
        expect(Booking.where(hold_id: live_hold.id).count).to eq(1)
      end

      it "creates exactly one ticket" do
        results
        expect(Ticket.count).to eq(1)
      end
    end

    context "when the hold has expired" do
      before { travel_to(hold.expires_at + 1.second) }

      after { travel_back }

      include_examples "a refused operation", :hold_expired
      include_examples "an operation that writes nothing", Booking

      it "issues no tickets" do
        expect { result }.not_to change(Ticket, :count)
      end
    end

    context "when the hold belongs to someone else" do
      let(:result) do
        described_class.call(user: create(:user), hold: hold, passengers: passengers,
                             boarding_stop_id: boarding_stop_id, dropping_stop_id: dropping_stop_id)
      end

      include_examples "a refused operation", :forbidden
      include_examples "an operation that writes nothing", Booking
    end

    context "when fewer passengers than seats are given" do
      let(:seat_count) { 2 }
      let(:passengers) { [ { name: "Only One" } ] }

      include_examples "a refused operation", :passenger_count_mismatch
      include_examples "an operation that writes nothing", Booking

      it "reports how many were expected" do
        expect(result.meta[:expected]).to eq(2)
      end
    end

    context "when a passenger name is blank" do
      let(:passengers) { [ { name: "   " } ] }

      include_examples "a refused operation", :passenger_name_missing
      include_examples "an operation that writes nothing", Booking
    end

    context "when the boarding point is on another trip" do
      let(:boarding_stop_id) { create(:trip, :with_stops).boarding_stops.first.id }

      include_examples "a refused operation", :stop_not_on_trip
      include_examples "an operation that writes nothing", Booking

      it "leaves the hold usable" do
        result
        expect(hold.reload).to be_active
      end
    end

    context "when the seats were released before confirmation" do
      before { HoldReleaseService.call(hold: hold, reason: :expired) }

      include_examples "a refused operation", :hold_expired
      include_examples "an operation that writes nothing", Booking
    end

    context "when the generated PNR collides with an existing one" do
      let(:taken_pnr) { "COLLIDES" }

      before do
        create(:booking, pnr: taken_pnr, trip: trip, user: user)
        allow(Booking).to receive(:generate_pnr).and_return(taken_pnr, "FRESHPNR")
      end

      it "returns a success" do
        expect(result).to be_success
      end

      it "retries with a new PNR" do
        expect(result.value.pnr).to eq("FRESHPNR")
      end
    end
  end
end
