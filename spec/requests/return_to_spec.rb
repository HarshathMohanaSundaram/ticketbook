require "rails_helper"

# Signing in should put you back where you were going, not on the home page.
RSpec.describe "Returning to the page you wanted" do
  let(:user) { create(:user) }
  let(:trip) { create(:trip, :with_seats, :with_stops, departs_at: 2.days.from_now) }

  it "returns to a protected page after signing in" do
    get bookings_path
    expect(response).to redirect_to(new_session_path)

    sign_in(user)

    expect(response).to redirect_to(bookings_path)
  end

  it "returns to the seat map when signing in from a public page" do
    # The seat map is public, so the "Sign in to book" link carries the path
    # rather than relying on require_authentication.
    get trip_path(trip)
    expect(response.body).to include("return_to=#{CGI.escape(trip_path(trip))}")

    get new_session_path(return_to: trip_path(trip))
    sign_in(user)

    expect(response).to redirect_to(trip_path(trip))
  end

  it "falls back to the home page when there is nowhere to return to" do
    sign_in(user)

    expect(response).to redirect_to(root_path)
  end

  it "ignores an off-site return_to, so the link cannot bounce you elsewhere" do
    get new_session_path(return_to: "https://evil.example.com/steal")
    sign_in(user)

    expect(response).to redirect_to(root_path)
  end

  it "ignores a protocol-relative return_to" do
    get new_session_path(return_to: "//evil.example.com")
    sign_in(user)

    expect(response).to redirect_to(root_path)
  end

  it "keeps the destination across the reset_session that sign-in performs" do
    get bookings_path              # stores the destination
    sign_in(user)                  # reset_session happens inside

    expect(response).to redirect_to(bookings_path)
    expect(session[:user_id]).to eq(user.id)
  end

  it "uses the destination only once" do
    get bookings_path
    sign_in(user)
    expect(response).to redirect_to(bookings_path)

    delete session_path
    sign_in(user)

    expect(response).to redirect_to(root_path)
  end
end
