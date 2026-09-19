require "rails_helper"

RSpec.describe AvailabilityCache, type: :model do
  let(:trip) { create(:trip) }

  def version_for(a_trip = trip)
    described_class.version_for(a_trip.origin_city_id, a_trip.destination_city_id, a_trip.service_date)
  end

  describe ".version_for" do
    context "when the corridor has never been touched" do
      it "returns zero rather than nil" do
        expect(version_for).to eq(0)
      end
    end
  end

  describe ".touch!" do
    it "increments the corridor's version" do
      expect { described_class.touch!(trip) }.to change { version_for }.from(0).to(1)
    end

    it "increments again on the next call" do
      described_class.touch!(trip)
      expect { described_class.touch!(trip) }.to change { version_for }.from(1).to(2)
    end

    context "with another day on the same route" do
      it "leaves that day untouched" do
        described_class.touch!(trip)
        other_day = described_class.version_for(trip.origin_city_id, trip.destination_city_id,
                                                trip.service_date + 1)
        expect(other_day).to eq(0)
      end
    end

    context "with the opposite direction" do
      it "leaves that corridor untouched" do
        described_class.touch!(trip)
        reverse = described_class.version_for(trip.destination_city_id, trip.origin_city_id,
                                              trip.service_date)
        expect(reverse).to eq(0)
      end
    end
  end

  describe ".key" do
    it "is namespaced so cache entries are distinguishable in Redis" do
      expect(described_class.key(1, 2, Date.new(2026, 9, 18))).to eq("avail:v1:1:2:2026-09-18")
    end
  end
end
