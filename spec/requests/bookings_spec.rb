require "rails_helper"

RSpec.describe "Bookings", type: :request do
  let(:user) { create(:user) }
  let(:trip) { create(:trip, :with_seats, :with_stops, seat_count: 4, departs_at: 8.hours.from_now) }
  let(:hold) do
    SeatHoldService.call(user: user, trip: trip,
                         seat_ids: trip.trip_seats.available.order(:id).first(2).map(&:id)).value
  end
  let(:valid_params) do
    {
      passengers: { "0" => { name: "Ravi Kumar", age: "34", gender: "male" },
                    "1" => { name: "Meera Rao", age: "31", gender: "female" } },
      boarding_stop_id: trip.boarding_stops.first.id,
      dropping_stop_id: trip.dropping_stops.first.id
    }
  end

  describe "GET /holds/:hold_id/booking/new" do
    context "when the hold is live" do
      before do
        sign_in(user)
        get new_hold_booking_path(hold)
      end

      it "returns a successful response" do
        expect(response).to have_http_status(:ok)
      end

      it "asks for a name per seat" do
        expect(response.body.scan('name="passengers[').size).to be >= 2
      end

      it "offers the trip's boarding points" do
        expect(response.body).to include("Boarding point")
      end
    end

    context "when the hold has expired" do
      before do
        sign_in(user)
        travel_to(hold.expires_at + 1.second) { get new_hold_booking_path(hold) }
      end

      it "sends the visitor back to the seat map" do
        expect(response).to redirect_to(trip)
      end
    end

    context "when signed out" do
      before { get new_hold_booking_path(hold) }

      it "sends the visitor to sign in" do
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "POST /holds/:hold_id/booking" do
    context "with passengers and pickup points" do
      before do
        sign_in(user)
        post hold_booking_path(hold), params: valid_params
      end

      it "creates the booking" do
        expect(Booking.count).to eq(1)
      end

      it "redirects to the ticket" do
        expect(response).to redirect_to(Booking.last)
      end

      it "confirms it in the flash" do
        expect(flash[:notice]).to include("Booking confirmed")
      end

      it "issues a ticket per passenger" do
        expect(Booking.last.tickets.count).to eq(2)
      end
    end

    context "when the same form is submitted twice" do
      before do
        sign_in(user)
        post hold_booking_path(hold), params: valid_params
        post hold_booking_path(hold), params: valid_params
      end

      it "creates only one booking" do
        expect(Booking.count).to eq(1)
      end

      it "says the booking was already confirmed" do
        expect(flash[:notice]).to include("already confirmed")
      end
    end

    context "when a passenger name is missing" do
      before do
        sign_in(user)
        post hold_booking_path(hold),
             params: valid_params.deep_merge(passengers: { "1" => { name: "" } })
      end

      it "creates no booking" do
        expect(Booking.count).to eq(0)
      end

      it "asks for the missing name" do
        expect(flash[:alert]).to include("name")
      end
    end

    context "when the hold expired while the form was open" do
      before do
        sign_in(user)
        travel_to(hold.expires_at + 1.second) { post hold_booking_path(hold), params: valid_params }
      end

      it "creates no booking" do
        expect(Booking.count).to eq(0)
      end

      it "explains that the hold expired" do
        expect(flash[:alert]).to include("expired")
      end
    end
  end

  describe "GET /bookings" do
    let!(:mine) { create(:booking, :with_seats, user: user, trip: trip) }
    let!(:theirs) { create(:booking, :with_seats, user: create(:user), trip: trip) }

    before do
      sign_in(user)
      get bookings_path
    end

    it "lists the visitor's own booking" do
      expect(response.body).to include(mine.pnr)
    end

    it "does not list anyone else's" do
      expect(response.body).not_to include(theirs.pnr)
    end
  end

  describe "GET /bookings/:pnr" do
    let(:booking) { create(:booking, :with_seats, user: user, trip: trip) }

    context "when it is the visitor's own booking" do
      before do
        sign_in(user)
        get booking_path(booking)
      end

      it "returns a successful response" do
        expect(response).to have_http_status(:ok)
      end

      it "shows the PNR" do
        expect(response.body).to include(booking.pnr)
      end

      it "offers cancellation while the window is open" do
        expect(response.body).to include("Cancel booking")
      end

      it "offers rescheduling" do
        expect(response.body).to include("Reschedule")
      end
    end

    context "when the booking belongs to someone else" do
      before do
        booking
        sign_in(create(:user))
        get booking_path(booking)
      end

      it "returns not found rather than forbidden" do
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when signed out" do
      before { get booking_path(booking) }

      it "sends the visitor to sign in" do
        expect(response).to redirect_to(new_session_path)
      end
    end
  end
end
