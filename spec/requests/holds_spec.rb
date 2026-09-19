require "rails_helper"

RSpec.describe "Holds", type: :request do
  let(:user) { create(:user) }
  let(:trip) { create(:trip, :with_seats, :with_stops, seat_count: 4, departs_at: 8.hours.from_now) }
  let(:seats) { trip.trip_seats.order(:id).to_a }

  describe "POST /trips/:trip_id/holds" do
    context "when signed out" do
      before { post trip_holds_path(trip), params: { seat_ids: seats.first.id.to_s } }

      it "sends the visitor to sign in" do
        expect(response).to redirect_to(new_session_path)
      end

      it "holds nothing" do
        expect(Hold.count).to eq(0)
      end
    end

    context "when signed in and the seats are free" do
      before do
        sign_in(user)
        post trip_holds_path(trip), params: { seat_ids: seats.first(2).map(&:id).join(",") }
      end

      it "creates the hold" do
        expect(Hold.count).to eq(1)
      end

      it "redirects to the hold page" do
        expect(response).to redirect_to(Hold.last)
      end

      it "holds both seats" do
        expect(Hold.last.trip_seats.count).to eq(2)
      end
    end

    context "when another passenger holds the seat" do
      before do
        SeatHoldService.call(user: create(:user), trip: trip, seat_ids: [ seats.first.id ])
        sign_in(user)
        post trip_holds_path(trip), params: { seat_ids: seats.first.id.to_s }
      end

      it "returns the visitor to the trip" do
        expect(response).to redirect_to(trip)
      end

      it "names the seat that was taken" do
        expect(flash[:alert]).to include(seats.first.seat_number)
      end
    end

    context "when no seat was selected" do
      before do
        sign_in(user)
        post trip_holds_path(trip), params: { seat_ids: "" }
      end

      it "asks for at least one seat" do
        expect(flash[:alert]).to include("Pick at least one seat")
      end
    end

    context "when more seats than the limit are selected" do
      let(:trip) { create(:trip, :with_seats, seat_count: Hold::MAX_SEATS + 1, departs_at: 8.hours.from_now) }

      before do
        sign_in(user)
        post trip_holds_path(trip), params: { seat_ids: seats.map(&:id).join(",") }
      end

      it "reports the limit" do
        expect(flash[:alert]).to include("at most #{Hold::MAX_SEATS}")
      end
    end
  end

  describe "GET /holds/:id" do
    let(:hold) { SeatHoldService.call(user: user, trip: trip, seat_ids: [ seats.first.id ]).value }

    context "when the hold is live" do
      before do
        sign_in(user)
        get hold_path(hold)
      end

      it "returns a successful response" do
        expect(response).to have_http_status(:ok)
      end

      it "shows the countdown" do
        expect(response.body).to include("hold-countdown")
      end

      it "offers the next step" do
        expect(response.body).to include("Continue to passenger details")
      end
    end

    context "when the hold has expired" do
      before do
        sign_in(user)
        travel_to(hold.expires_at + 1.second) { get hold_path(hold) }
      end

      it "sends the visitor back to the seat map" do
        expect(response).to redirect_to(trip)
      end

      it "explains that the hold expired" do
        expect(flash[:alert]).to include("expired")
      end
    end

    context "when the hold belongs to someone else" do
      before do
        hold
        sign_in(create(:user))
        get hold_path(hold)
      end

      it "returns not found rather than forbidden" do
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /holds/:id" do
    let!(:hold) { SeatHoldService.call(user: user, trip: trip, seat_ids: [ seats.first.id ]).value }

    before do
      sign_in(user)
      delete hold_path(hold)
    end

    it "redirects with a See Other so Turbo follows with a GET" do
      expect(response).to have_http_status(:see_other)
    end

    it "releases the hold" do
      expect(hold.reload).to be_released
    end

    it "puts the seat back on sale" do
      expect(seats.first.reload).to be_available
    end
  end
end
