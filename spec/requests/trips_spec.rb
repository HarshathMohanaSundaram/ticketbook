require "rails_helper"

RSpec.describe "Trips", type: :request do
  let(:origin) { create(:city, name: "Bangalore", slug: "bangalore") }
  let(:destination) { create(:city, name: "Chennai", slug: "chennai") }
  let(:operator) { create(:operator, name: "VRL Travels", rating: 4.5) }

  def trip_on(departs_at:, bus_type: "ac", berth_type: "seater", fare: 90_000, amenities: %w[wifi], seats: 4)
    create(:trip, :with_seats, :with_stops,
           operator: operator,
           bus: create(:bus, operator: operator, bus_type: bus_type, berth_type: berth_type,
                             amenity_codes: amenities),
           origin_city: origin, destination_city: destination,
           departs_at: departs_at, arrives_at: departs_at + 6.hours,
           base_fare_paise: fare, seat_count: seats)
  end

  let!(:trip) { trip_on(departs_at: 2.days.from_now.change(hour: 21)) }
  let(:search_date) { trip.service_date }

  describe "GET /trips" do
    context "when nothing has been searched for yet" do
      before { get trips_path }

      it "returns a successful response" do
        expect(response).to have_http_status(:ok)
      end

      it "invites the visitor to pick a route" do
        expect(response.body).to include("Pick where you are going")
      end
    end

    context "with a route and date that has departures" do
      before { get trips_path(from: origin.slug, to: destination.slug, date: search_date) }

      it "lists the matching trip" do
        expect(response.body).to include(operator.name)
      end

      it "shows how many seats are left" do
        expect(response.body).to include("4 seats left")
      end

      it "offers the seat map" do
        expect(response.body).to include("View seats")
      end
    end

    context "when every seat on the trip is taken" do
      before do
        trip.trip_seats.update_all(status: "booked")
        get trips_path(from: origin.slug, to: destination.slug, date: search_date)
      end

      it "marks the trip sold out" do
        expect(response.body).to include("Sold out")
      end

      it "offers no seat map" do
        expect(response.body).not_to include("View seats")
      end
    end

    context "when a filter excludes every trip" do
      before { get trips_path(from: origin.slug, to: destination.slug, date: search_date, bus_type: "non_ac") }

      it "says the filters matched nothing" do
        expect(response.body).to include("No buses match these filters")
      end

      it "offers a way to clear them" do
        expect(response.body).to include("Clear filters")
      end
    end

    context "when every departure for the day has left" do
      before do
        travel_to(trip.departs_at + 1.hour) do
          get trips_path(from: origin.slug, to: destination.slug, date: search_date)
        end
      end

      it "explains that the buses have gone rather than that none exist" do
        expect(response.body).to include("already left")
      end

      it "offers the next day" do
        expect(response.body).to include("Show #{(search_date + 1).strftime('%-d %b')} instead")
      end
    end

    context "when the route has no service at all" do
      before { get trips_path(from: origin.slug, to: create(:city, slug: "nowhere").slug, date: search_date) }

      it "says the route is not served" do
        expect(response.body).to include("do not run buses on this route")
      end
    end

    context "with an unknown city" do
      before { get trips_path(from: "atlantis", to: destination.slug, date: search_date) }

      it "reports the bad city rather than failing" do
        expect(response.body).to include("is not a city we serve")
      end

      it "still returns a successful response" do
        expect(response).to have_http_status(:ok)
      end
    end

    context "with a date in the past" do
      before { get trips_path(from: origin.slug, to: destination.slug, date: Date.current - 1) }

      it "reports the bad date" do
        expect(response.body).to include("is in the past")
      end
    end

    context "with filters that match" do
      let!(:cheaper) { trip_on(departs_at: search_date.in_time_zone(Trip::TZ).change(hour: 6), bus_type: "non_ac", fare: 50_000, amenities: []) }

      it "keeps a trip that matches the bus type" do
        get trips_path(from: origin.slug, to: destination.slug, date: search_date, bus_type: "non_ac")
        expect(response.body).to include("Non-AC")
      end

      it "drops a trip priced outside the band" do
        get trips_path(from: origin.slug, to: destination.slug, date: search_date, max_price: 600)
        expect(response.body).not_to include("&#8377;900")
      end

      it "keeps only trips with the requested amenity" do
        get trips_path(from: origin.slug, to: destination.slug, date: search_date, amenities: [ "wifi" ])
        expect(response.body.scan("<article").size).to eq(1)
      end
    end

    it "does not require signing in" do
      get trips_path(from: origin.slug, to: destination.slug, date: search_date)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /trips/:id" do
    context "when the trip is open for booking" do
      before { get trip_path(trip) }

      it "returns a successful response" do
        expect(response).to have_http_status(:ok)
      end

      it "renders the seat map" do
        expect(response.body).to include('data-controller="seat-selection"')
      end

      it "lists the boarding points" do
        expect(response.body).to include("Boarding points")
      end

      it "asks a signed out visitor to sign in before holding" do
        expect(response.body).to include("Sign in to book")
      end
    end

    context "when the trip is sold out" do
      before do
        trip.trip_seats.update_all(status: "booked")
        get trip_path(trip)
      end

      it "says so instead of showing a seat map" do
        expect(response.body).to include("sold out")
      end
    end

    context "when the trip is too close to departure" do
      before do
        travel_to(trip.departs_at - 10.minutes) { get trip_path(trip) }
      end

      it "says booking has closed" do
        expect(response.body).to include("no longer open for booking")
      end
    end

    context "when the trip does not exist" do
      it "returns not found" do
        get trip_path(id: 0)
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
