require "rails_helper"

RSpec.describe TripSearchQuery do
  let(:origin) { create(:city) }
  let(:destination) { create(:city) }
  let(:operator) { create(:operator, rating: 4.5) }

  let!(:trip) do
    create(:trip, :with_seats, operator: operator, bus: create(:bus, operator: operator),
                               origin_city: origin, destination_city: destination,
                               departs_at: 2.days.from_now.change(hour: 21), seat_count: 4)
  end

  def form(**overrides)
    TripSearchForm.new({ from: origin.slug, to: destination.slug,
                         date: trip.departs_at.to_date }.merge(overrides))
  end

  def count_queries
    count = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name].to_s =~ /SCHEMA|TRANSACTION/
    end
    yield
    ActiveSupport::Notifications.unsubscribe(sub)
    count
  end

  describe "results" do
    it "returns the same trips whether cached or not" do
      first = described_class.new(form).call.to_a
      second = described_class.new(form).call.to_a

      expect(first).to eq([ trip ])
      expect(second).to eq(first)
    end

    it "preserves the sort order taken from the cache" do
      later = create(:trip, :with_seats, operator: operator, bus: create(:bus, operator: operator),
                                         origin_city: origin, destination_city: destination,
                                         # +1h keeps it on the same service date; +3h would
                                         # roll past midnight and on_date would rightly drop it.
                                         departs_at: trip.departs_at + 1.hour, seat_count: 4)

      described_class.new(form(sort: "departure")).call.to_a   # warm
      expect(described_class.new(form(sort: "departure")).call.to_a).to eq([ trip, later ])
    end

    it "skips the filtering query on a second search" do
      warm = count_queries { described_class.new(form).call.to_a }
      cached = count_queries { described_class.new(form).call.to_a }

      expect(cached).to be < warm
    end
  end

  describe "the cache key" do
    it "is stable when the amenity order changes" do
      a = described_class.new(form(amenities: %w[wifi cctv])).cache_key
      b = described_class.new(form(amenities: %w[cctv wifi])).cache_key

      expect(a).to eq(b)
    end

    it "differs when a filter value changes" do
      expect(described_class.new(form(bus_type: "ac")).cache_key)
        .not_to eq(described_class.new(form(bus_type: "non_ac")).cache_key)
    end

    it "differs per date and per corridor" do
      expect(described_class.new(form(date: trip.departs_at.to_date + 1)).cache_key)
        .not_to eq(described_class.new(form).cache_key)
    end

    it "changes when the corridor's availability version is bumped" do
      before_key = described_class.new(form).cache_key
      AvailabilityCache.touch!(trip)

      expect(described_class.new(form).cache_key).not_to eq(before_key)
    end
  end

  describe "serving stale data" do
    it "does not serve a trip that was removed from the corridor after caching" do
      described_class.new(form).call.to_a           # warm the cache
      trip.update!(status: "cancelled")
      AvailabilityCache.touch!(trip)                # what the services do

      expect(described_class.new(form).call.to_a).to be_empty
    end

    it "reads trip rows fresh even on a cache hit, so a repriced trip is current" do
      described_class.new(form).call.to_a           # warm
      trip.update!(base_fare_paise: 250_000)

      expect(described_class.new(form).call.first.base_fare_paise).to eq(250_000)
    end
  end
end
