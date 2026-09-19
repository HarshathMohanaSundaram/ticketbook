require "rails_helper"

RSpec.describe BoardingStop, type: :model do
  include_examples "a trip stop subclass", :boarding_stop, "boarding"

  describe "how a trip reaches it" do
    let(:trip) { create(:trip) }
    let!(:boarding) { create(:boarding_stop, trip: trip, scheduled_at: trip.departs_at) }
    let!(:dropping) { create(:dropping_stop, trip: trip, scheduled_at: trip.arrives_at) }

    it "appears in the trip's boarding stops" do
      expect(trip.boarding_stops).to eq([ boarding ])
    end

    it "does not appear among the dropping stops" do
      expect(trip.dropping_stops).not_to include(boarding)
    end
  end

  describe "how a booking reaches it" do
    let(:trip) { create(:trip, :with_stops) }

    it "can be assigned as a booking's boarding stop" do
      booking = build(:booking, trip: trip, boarding_stop: trip.boarding_stops.first)
      expect(booking).to be_valid
    end

    it "cannot be assigned as a booking's dropping stop" do
      expect { build(:booking, dropping_stop: create(:boarding_stop)) }
        .to raise_error(ActiveRecord::AssociationTypeMismatch)
    end
  end
end
