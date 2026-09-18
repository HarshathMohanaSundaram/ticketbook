require "rails_helper"

RSpec.describe "Reschedules", type: :request do
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

  let(:target_seat) { later_trip.trip_seats.available.order(:id).first }

  describe "GET /bookings/:pnr/reschedule/new" do
    context "when no departure has been picked yet" do
      before do
        sign_in(user)
        get new_booking_reschedule_path(booking)
      end

      it "returns a successful response" do
        expect(response).to have_http_status(:ok)
      end

      it "lists another departure on the same route" do
        expect(response.body).to include(I18n.l(later_trip.departs_at, format: :day_and_time))
      end

      it "shows no seat map until one is chosen" do
        expect(response.body).not_to include("Move my booking here")
      end
    end

    context "when a rival operator also runs the route" do
      let!(:rival_trip) { trip_on(departs_at: 2.days.from_now, operator: create(:operator)) }

      before do
        sign_in(user)
        get new_booking_reschedule_path(booking)
      end

      it "excludes the rival's departure" do
        expect(response.body).not_to include(rival_trip.bus.registration_number)
      end
    end

    context "when a departure has been picked" do
      before do
        sign_in(user)
        get new_booking_reschedule_path(booking, trip_id: later_trip.id)
      end

      it "renders the seat map" do
        expect(response.body).to include('data-controller="seat-selection"')
      end

      it "offers to move the booking" do
        expect(response.body).to include("Move my booking here")
      end

      it "limits the selection to the passenger count" do
        expect(response.body).to include('data-seat-selection-max-seats-value="1"')
      end
    end

    context "when the original is inside its cancellation window" do
      before do
        sign_in(user)
        travel_to(original_trip.departs_at - 30.minutes) { get new_booking_reschedule_path(booking) }
      end

      it "redirects back to the ticket" do
        expect(response).to redirect_to(booking)
      end

      it "explains that rescheduling has closed" do
        expect(flash[:alert]).to include("Rescheduling closed")
      end
    end

    context "when the booking belongs to someone else" do
      before do
        booking
        sign_in(create(:user))
        get new_booking_reschedule_path(booking)
      end

      it "returns not found" do
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /bookings/:pnr/reschedule" do
    context "with a departure and a seat" do
      before do
        sign_in(user)
        post booking_reschedule_path(booking), params: { trip_id: later_trip.id, seat_ids: target_seat.id.to_s }
      end

      let(:successor) { Booking.find_by(rescheduled_from_id: booking.id) }

      it "issues a successor booking" do
        expect(successor).to be_present
      end

      it "redirects to the new ticket" do
        expect(response).to redirect_to(successor)
      end

      it "marks the original rescheduled" do
        expect(booking.reload).to be_rescheduled
      end

      it "books the chosen seat" do
        expect(target_seat.reload).to be_booked
      end

      it "carries the passenger across" do
        expect(successor.tickets.first.passenger_name).to eq("Ravi Kumar")
      end
    end

    context "when the seat was taken while the page was open" do
      before do
        sign_in(user)
        SeatHoldService.call(user: create(:user), trip: later_trip, seat_ids: [ target_seat.id ])
        post booking_reschedule_path(booking), params: { trip_id: later_trip.id, seat_ids: target_seat.id.to_s }
      end

      it "says the seat was taken" do
        expect(flash[:alert]).to include("was just taken")
      end

      it "leaves the original booking confirmed" do
        expect(booking.reload).to be_confirmed
      end

      it "issues no successor" do
        expect(Booking.where(rescheduled_from_id: booking.id)).to be_empty
      end
    end

    context "when no departure was chosen" do
      before do
        sign_in(user)
        post booking_reschedule_path(booking), params: { seat_ids: target_seat.id.to_s }
      end

      it "asks for a departure" do
        expect(flash[:alert]).to include("Pick a departure")
      end
    end

    context "when the window has closed" do
      before do
        sign_in(user)
        travel_to(original_trip.departs_at - 30.minutes) do
          post booking_reschedule_path(booking), params: { trip_id: later_trip.id, seat_ids: target_seat.id.to_s }
        end
      end

      it "explains that rescheduling has closed" do
        expect(flash[:alert]).to include("Rescheduling closed")
      end

      it "leaves the original booking confirmed" do
        expect(booking.reload).to be_confirmed
      end
    end
  end

  describe "the two tickets afterwards" do
    let(:successor) { Booking.find_by(rescheduled_from_id: booking.id) }

    before do
      sign_in(user)
      post booking_reschedule_path(booking), params: { trip_id: later_trip.id, seat_ids: target_seat.id.to_s }
    end

    it "shows where the new booking came from" do
      get booking_path(successor)
      expect(response.body).to include("Rescheduled from")
    end

    it "links back to the original PNR" do
      get booking_path(successor)
      expect(response.body).to include(booking.pnr)
    end

    it "shows where the old booking went" do
      get booking_path(booking)
      expect(response.body).to include("Moved to")
    end
  end
end
