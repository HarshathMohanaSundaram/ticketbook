require "rails_helper"

RSpec.describe "Reschedules" do
  let(:user) { create(:user) }
  let(:operator) { create(:operator) }
  let(:origin) { create(:city) }
  let(:destination) { create(:city) }

  def trip_on(departs_at:, operator: self.operator)
    create(:trip, :with_seats, :with_stops,
           operator: operator, bus: create(:bus, operator: operator),
           origin_city: origin, destination_city: destination,
           departs_at: departs_at, arrives_at: departs_at + 6.hours, seat_count: 4)
  end

  let!(:original_trip) { trip_on(departs_at: 8.hours.from_now) }
  let!(:later_trip) { trip_on(departs_at: 2.days.from_now) }

  let(:booking) do
    hold = SeatHoldService.call(user: user, trip: original_trip,
                                seat_ids: [ original_trip.trip_seats.available.order(:id).first.id ]).value
    BookingConfirmationService.call(
      user: user, hold: hold, passengers: [ { name: "Ravi Kumar" } ],
      boarding_stop_id: original_trip.boarding_stops.first.id,
      dropping_stop_id: original_trip.dropping_stops.first.id
    ).value
  end

  it "lists other departures on the same route and operator" do
    rival = trip_on(departs_at: 2.days.from_now, operator: create(:operator))
    sign_in(user)

    get new_booking_reschedule_path(booking)

    expect(response.body).to include(I18n.l(later_trip.departs_at, format: :day_and_time))
    expect(response.body).not_to include(rival.bus.registration_number)
  end

  it "shows a seat map once a departure is picked" do
    sign_in(user)

    get new_booking_reschedule_path(booking, trip_id: later_trip.id)

    expect(response.body).to include("data-controller=\"seat-selection\"")
    expect(response.body).to include("Move my booking here")
  end

  it "moves the booking and releases the old seats" do
    sign_in(user)
    old_seat = booking.trip_seats.first
    new_seat = later_trip.trip_seats.available.order(:id).first

    post booking_reschedule_path(booking), params: { trip_id: later_trip.id, seat_ids: new_seat.id.to_s }

    successor = Booking.find_by!(rescheduled_from_id: booking.id)
    expect(response).to redirect_to(successor)
    expect(booking.reload).to be_rescheduled
    expect(old_seat.reload).to be_available
    expect(new_seat.reload).to be_booked
    expect(successor.tickets.first.passenger_name).to eq("Ravi Kumar")
  end

  it "reports a seat taken while the page was open, leaving the booking alone" do
    sign_in(user)
    wanted = later_trip.trip_seats.available.order(:id).first
    SeatHoldService.call(user: create(:user), trip: later_trip, seat_ids: [ wanted.id ])

    post booking_reschedule_path(booking), params: { trip_id: later_trip.id, seat_ids: wanted.id.to_s }

    expect(flash[:alert]).to include("was just taken")
    expect(booking.reload).to be_confirmed
    expect(Booking.where(rescheduled_from_id: booking.id)).to be_empty
  end

  it "refuses inside the one hour cutoff" do
    sign_in(user)
    seat = later_trip.trip_seats.available.order(:id).first

    travel_to(original_trip.departs_at - 30.minutes) do
      post booking_reschedule_path(booking), params: { trip_id: later_trip.id, seat_ids: seat.id.to_s }
    end

    expect(flash[:alert]).to include("Rescheduling closed")
    expect(booking.reload).to be_confirmed
  end

  it "will not touch another passenger's booking" do
    sign_in(create(:user))

    get new_booking_reschedule_path(booking)

    expect(response).to have_http_status(:not_found)
  end

  it "shows the link between the two bookings afterwards" do
    sign_in(user)
    seat = later_trip.trip_seats.available.order(:id).first
    post booking_reschedule_path(booking), params: { trip_id: later_trip.id, seat_ids: seat.id.to_s }
    successor = Booking.find_by!(rescheduled_from_id: booking.id)

    get booking_path(successor)
    expect(response.body).to include("Rescheduled from", booking.pnr)

    get booking_path(booking)
    expect(response.body).to include("Moved to", successor.pnr)
  end
end
