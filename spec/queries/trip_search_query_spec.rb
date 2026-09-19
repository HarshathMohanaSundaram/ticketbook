require "rails_helper"

RSpec.describe TripSearchQuery, type: :query do
  subject(:query) { described_class.new(form) }

  let(:origin) { create(:city) }
  let(:destination) { create(:city) }
  let(:operator) { create(:operator, rating: 4.5) }

  let!(:trip) do
    create(:trip, :with_seats, operator: operator, bus: create(:bus, operator: operator),
                               origin_city: origin, destination_city: destination,
                               departs_at: 2.days.from_now.change(hour: 21), seat_count: 4)
  end

  let(:base_params) { { from: origin.slug, to: destination.slug, date: trip.service_date } }
  let(:form) { TripSearchForm.new(base_params) }

  def queries_run
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name].to_s =~ /SCHEMA|TRANSACTION/
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscriber)
    count
  end

  describe "#call" do
    context "with a valid search" do
      it "returns the matching trip" do
        expect(query.call.to_a).to eq([ trip ])
      end
    end

    context "with an incomplete search" do
      let(:form) { TripSearchForm.new(from: origin.slug) }

      it "returns nothing rather than every trip" do
        expect(query.call).to be_empty
      end
    end

    context "when the search is repeated" do
      before { query.call.to_a }

      it "returns the same trips" do
        expect(described_class.new(form).call.to_a).to eq([ trip ])
      end

      it "runs fewer queries than the first time" do
        warm = queries_run { described_class.new(form).call.to_a }
        Rails.cache.clear
        cold = queries_run { described_class.new(form).call.to_a }

        expect(warm).to be < cold
      end
    end

    context "when several trips match" do
      let!(:later) do
        create(:trip, :with_seats, operator: operator, bus: create(:bus, operator: operator),
                                   origin_city: origin, destination_city: destination,
                                   departs_at: trip.departs_at + 1.hour, seat_count: 4)
      end

      before { described_class.new(TripSearchForm.new(base_params.merge(sort: "departure"))).call.to_a }

      it "preserves the cached ordering" do
        repeated = described_class.new(TripSearchForm.new(base_params.merge(sort: "departure"))).call
        expect(repeated.to_a).to eq([ trip, later ])
      end
    end

    context "when a trip is repriced after the search was cached" do
      before do
        query.call.to_a
        trip.update!(base_fare_paise: 250_000)
      end

      # Only the ids are cached; the rows are read fresh, so stale prices cannot
      # be served.
      it "shows the new fare" do
        expect(described_class.new(form).call.first.base_fare_paise).to eq(250_000)
      end
    end

    context "when a trip is cancelled and the corridor is invalidated" do
      before do
        query.call.to_a
        trip.update!(status: "cancelled")
        AvailabilityCache.touch!(trip)
      end

      it "drops the trip from the results" do
        expect(described_class.new(form).call).to be_empty
      end
    end
  end

  describe "#cache_key" do
    context "when the same amenities arrive in a different order" do
      let(:one) { described_class.new(TripSearchForm.new(base_params.merge(amenities: %w[wifi cctv]))) }
      let(:other) { described_class.new(TripSearchForm.new(base_params.merge(amenities: %w[cctv wifi]))) }

      it "is the same key, so one entry serves both" do
        expect(one.cache_key).to eq(other.cache_key)
      end
    end

    context "when a filter value differs" do
      it "is a different key" do
        ac = described_class.new(TripSearchForm.new(base_params.merge(bus_type: "ac")))
        non_ac = described_class.new(TripSearchForm.new(base_params.merge(bus_type: "non_ac")))

        expect(ac.cache_key).not_to eq(non_ac.cache_key)
      end
    end

    context "when the date differs" do
      it "is a different key" do
        other_day = described_class.new(TripSearchForm.new(base_params.merge(date: trip.service_date + 1)))
        expect(other_day.cache_key).not_to eq(query.cache_key)
      end
    end

    context "when the corridor's availability version is bumped" do
      it "is a different key" do
        expect { AvailabilityCache.touch!(trip) }.to change { described_class.new(form).cache_key }
      end
    end
  end

  describe "#empty_reason" do
    context "when trips exist but every one has departed" do
      it "reports that they have all left" do
        travel_to(trip.departs_at + 1.hour) do
          expect(described_class.new(TripSearchForm.new(base_params)).empty_reason).to eq(:all_departed)
        end
      end
    end

    context "when the route has no service that day" do
      let(:form) { TripSearchForm.new(base_params.merge(date: trip.service_date + 3)) }

      it "reports that the route is not served" do
        expect(query.empty_reason).to eq(:no_service)
      end
    end

    context "when filters excluded everything" do
      let(:form) { TripSearchForm.new(base_params.merge(min_price: 99_999)) }

      it "reports that the filters are to blame" do
        expect(query.empty_reason).to eq(:filtered_out)
      end
    end

    context "when the search itself is incomplete" do
      let(:form) { TripSearchForm.new({}) }

      it "reports nothing" do
        expect(query.empty_reason).to be_nil
      end
    end
  end
end
