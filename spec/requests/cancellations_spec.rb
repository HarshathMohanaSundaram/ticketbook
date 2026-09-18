require "rails_helper"

RSpec.describe "Cancellations" do
  let(:user) { create(:user) }
  let(:trip) { create(:trip, departs_at: 6.hours.from_now) }
  let(:booking) do
    create(:booking, :with_seats, user: user, trip: trip, total_paise: 120_000,
                                  departs_at: trip.departs_at)
  end

  it "cancels a booking and reports the refund" do
    sign_in(user)

    post booking_cancellation_path(booking)

    expect(response).to redirect_to(booking)
    follow_redirect!
    expect(flash[:notice]).to include("1,150")
    expect(booking.reload).to be_cancelled
    expect(booking.trip_seats.map(&:reload).map(&:status)).to all(eq("available"))
  end

  it "shows the cancel button only while cancellation is open" do
    sign_in(user)

    get booking_path(booking)
    expect(response.body).to include("Cancel booking")
    # The deadline carries its date: a bare time is ambiguous when the bus
    # leaves tomorrow.
    expect(response.body).to include(I18n.l(booking.cancellation_deadline, format: :day_and_time))

    travel_to(trip.departs_at - 30.minutes) do
      get booking_path(booking)
      expect(response.body).not_to include("Cancel booking")
      expect(response.body).to include("Cancellation closed")
    end
  end

  it "refuses inside the one hour window" do
    sign_in(user)

    travel_to(trip.departs_at - 30.minutes) do
      post booking_cancellation_path(booking)
    end

    expect(flash[:alert]).to include("Cancellation closed")
    expect(booking.reload).to be_confirmed
  end

  it "does not let one passenger cancel another's booking" do
    sign_in(create(:user))

    post booking_cancellation_path(booking)

    # 404 rather than 403: the lookup is scoped to the current user, so the app
    # never confirms that someone else's PNR exists.
    expect(response).to have_http_status(:not_found)
    expect(booking.reload).to be_confirmed
  end

  it "sends a signed out visitor to sign in" do
    post booking_cancellation_path(booking)

    expect(response).to redirect_to(new_session_path)
    expect(booking.reload).to be_confirmed
  end

  it "shows the refund breakdown after cancellation" do
    sign_in(user)
    post booking_cancellation_path(booking)

    get booking_path(booking)

    expect(response.body).to include("Cancellation fee", "Refund", "1,150")
  end
end
