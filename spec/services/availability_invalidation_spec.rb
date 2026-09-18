require "rails_helper"

# The brief asks for the mechanism that expires cached search results when a
# booking or cancellation changes seat availability. These specs pin that wiring.
RSpec.describe "search cache invalidation" do
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

  it "bumps the version when a booking is confirmed" do
    expect { confirmed_booking }.to change { version }.by(1)
  end

  it "bumps the version when a booking is cancelled" do
    booking = confirmed_booking

    expect { CancellationService.call(booking: booking, actor: user) }.to change { version }.by(1)
  end

  it "bumps both corridors when a booking is rescheduled" do
    booking = confirmed_booking
    target = trip_on(departs_at: 2.days.from_now)

    expect {
      RescheduleService.call(booking: booking, target_trip: target, actor: user,
                             seat_ids: [ target.trip_seats.available.order(:id).first.id ])
    }.to change { version(trip) }.by(1).and change { version(target) }.by(1)
  end

  it "bumps when trips are marked departed" do
    past = trip_on(departs_at: 2.hours.from_now)
    travel_to(past.departs_at + 1.minute) do
      expect { TripManagementJob.perform_now }.to change { version(past) }.by(1)
    end
  end

  it "does not bump for a hold, which changes no trip in the list" do
    expect {
      SeatHoldService.call(user: user, trip: trip,
                           seat_ids: [ trip.trip_seats.available.order(:id).first.id ])
    }.not_to change { version }
  end

  it "makes the next search miss the cache" do
    form = TripSearchForm.new(from: origin.slug, to: destination.slug, date: trip.service_date)
    key_before = TripSearchQuery.new(form).cache_key

    confirmed_booking

    expect(TripSearchQuery.new(form).cache_key).not_to eq(key_before)
  end

  it "never caches seat availability -- the count drops with no invalidation at all" do
    trip.trip_seats.available.count.tap do |before|
      confirmed_booking
      expect(TripSeat.available_counts_by_trip([ trip.id ])[trip.id]).to eq(before - 1)
    end
  end
end
