require "rails_helper"

# The brief asks for the mechanism that expires cached search results when a
# booking or cancellation changes seat availability. These pin the wiring: which
# operations bump the corridor's version, and which deliberately do not.
RSpec.describe "search cache invalidation", type: :service do
  let(:user) { create(:user) }
  let(:operator) { create(:operator) }
  let(:origin) { create(:city) }
  let(:destination) { create(:city) }

  def trip_on(departs_at:)
    create(:trip, :with_seats, :with_stops, operator: operator,
           bus: create(:bus, operator: operator), origin_city: origin,
           destination_city: destination, departs_at: departs_at,
           arrives_at: departs_at + 6.hours, seat_count: 4)
  end

  let(:trip) { trip_on(departs_at: 8.hours.from_now) }

  def version(for_trip = trip)
    AvailabilityCache.version_for(for_trip.origin_city_id, for_trip.destination_city_id,
                                  for_trip.service_date)
  end

  def confirmed_booking(on: trip)
    hold = SeatHoldService.call(user: user, trip: on,
                                seat_ids: [ on.trip_seats.available.order(:id).first.id ]).value
    BookingConfirmationService.call(user: user, hold: hold, passengers: [ { name: "Ravi" } ],
                                    boarding_stop_id: on.boarding_stops.first.id,
                                    dropping_stop_id: on.dropping_stops.first.id).value
  end

  context "when a booking is confirmed" do
    it "bumps the corridor's version" do
      expect { confirmed_booking }.to change { version }.by(1)
    end

    it "makes the next search miss the cache" do
      form = TripSearchForm.new(from: origin.slug, to: destination.slug, date: trip.service_date)
      expect { confirmed_booking }.to change { TripSearchQuery.new(form).cache_key }
    end
  end

  context "when a booking is cancelled" do
    let!(:booking) { confirmed_booking }

    it "bumps the corridor's version" do
      expect { CancellationService.call(booking: booking, actor: user) }.to change { version }.by(1)
    end
  end

  context "when a booking is rescheduled" do
    let!(:booking) { confirmed_booking }
    let(:target) { trip_on(departs_at: 2.days.from_now) }

    it "bumps the corridor being left" do
      expect {
        RescheduleService.call(booking: booking, target_trip: target, actor: user,
                               seat_ids: [ target.trip_seats.available.order(:id).first.id ])
      }.to change { version(trip) }.by(1)
    end

    it "bumps the corridor being joined" do
      expect {
        RescheduleService.call(booking: booking, target_trip: target, actor: user,
                               seat_ids: [ target.trip_seats.available.order(:id).first.id ])
      }.to change { version(target) }.by(1)
    end
  end

  context "when trips are marked departed" do
    let!(:past) { trip_on(departs_at: 2.hours.from_now) }

    it "bumps that corridor" do
      travel_to(past.departs_at + 1.minute) do
        expect { TripManagementJob.perform_now }.to change { version(past) }.by(1)
      end
    end
  end

  context "when a seat is merely held" do
    # Holds are the highest-frequency write in the app and change no trip in the
    # list, so bumping here would destroy the cache faster than it could be read.
    it "does not bump the version" do
      expect {
        SeatHoldService.call(user: user, trip: trip,
                             seat_ids: [ trip.trip_seats.available.order(:id).first.id ])
      }.not_to change { version }
    end
  end

  context "when a hold is released" do
    let!(:hold) do
      SeatHoldService.call(user: user, trip: trip,
                           seat_ids: [ trip.trip_seats.available.order(:id).first.id ]).value
    end

    it "does not bump the version" do
      expect { HoldReleaseService.call(hold: hold, reason: :released) }.not_to change { version }
    end
  end

  describe "what is never cached" do
    # Availability is read live on every request, so the seat count is correct
    # whether or not any invalidation ever happens.
    it "reflects a booking in the seat count with no invalidation involved" do
      before_count = TripSeat.available_counts_by_trip([ trip.id ])[trip.id]
      confirmed_booking

      expect(TripSeat.available_counts_by_trip([ trip.id ])[trip.id]).to eq(before_count - 1)
    end
  end
end
