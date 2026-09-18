require "rails_helper"

RSpec.describe "Cancellations", type: :request do
  let(:user) { create(:user) }
  let(:trip) { create(:trip, departs_at: 6.hours.from_now) }
  let(:booking) do
    create(:booking, :with_seats, user: user, trip: trip, total_paise: 120_000,
                                  departs_at: trip.departs_at)
  end

  describe "POST /bookings/:pnr/cancellation" do
    context "when the window is open" do
      before do
        sign_in(user)
        post booking_cancellation_path(booking)
      end

      it "redirects back to the ticket" do
        expect(response).to redirect_to(booking)
      end

      it "cancels the booking" do
        expect(booking.reload).to be_cancelled
      end

      it "reports the refund in the flash" do
        expect(flash[:notice]).to include("1,150")
      end

      it "returns the seats to the pool" do
        expect(booking.trip_seats.map(&:reload)).to all(be_available)
      end
    end

    context "when the window has closed" do
      before do
        sign_in(user)
        travel_to(trip.departs_at - 30.minutes) { post booking_cancellation_path(booking) }
      end

      it "explains that cancellation closed" do
        expect(flash[:alert]).to include("Cancellation closed")
      end

      it "leaves the booking confirmed" do
        expect(booking.reload).to be_confirmed
      end
    end

    context "when the booking has already been cancelled" do
      before do
        sign_in(user)
        post booking_cancellation_path(booking)
        post booking_cancellation_path(booking)
      end

      it "says it was already cancelled" do
        expect(flash[:notice]).to include("already cancelled")
      end

      it "keeps the original refund" do
        expect(booking.reload.refund_paise).to eq(115_000)
      end
    end

    context "when the booking belongs to someone else" do
      before do
        booking
        sign_in(create(:user))
        post booking_cancellation_path(booking)
      end

      it "returns not found rather than forbidden" do
        expect(response).to have_http_status(:not_found)
      end

      it "leaves the booking confirmed" do
        expect(booking.reload).to be_confirmed
      end
    end

    context "when signed out" do
      before { post booking_cancellation_path(booking) }

      it "sends the visitor to sign in" do
        expect(response).to redirect_to(new_session_path)
      end

      it "cancels nothing" do
        expect(booking.reload).to be_confirmed
      end
    end
  end

  describe "the ticket page" do
    before { sign_in(user) }

    context "while cancellation is open" do
      before { get booking_path(booking) }

      it "offers the cancel button" do
        expect(response.body).to include("Cancel booking")
      end

      it "shows the deadline with its date" do
        expect(response.body).to include(I18n.l(booking.cancellation_deadline, format: :day_and_time))
      end

      it "shows what would be refunded" do
        expect(response.body).to include("1,150")
      end
    end

    context "once the window has closed" do
      before { travel_to(trip.departs_at - 30.minutes) { get booking_path(booking) } }

      it "hides the cancel button" do
        expect(response.body).not_to include("Cancel booking")
      end

      it "says cancellation has closed" do
        expect(response.body).to include("Cancellation closed")
      end
    end

    context "after cancelling" do
      before do
        post booking_cancellation_path(booking)
        get booking_path(booking)
      end

      it "shows the fee that was charged" do
        expect(response.body).to include("Cancellation fee")
      end

      it "shows the refund" do
        expect(response.body).to include("1,150")
      end

      it "shows when it was cancelled" do
        expect(response.body).to include("Cancelled")
      end
    end
  end
end
