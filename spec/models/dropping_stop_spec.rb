require "rails_helper"

RSpec.describe DroppingStop, type: :model do
  include_examples "a trip stop subclass", :dropping_stop, "dropping"

  describe "how a trip reaches it" do
    let(:trip) { create(:trip) }
    let!(:dropping) { create(:dropping_stop, trip: trip, scheduled_at: trip.arrives_at) }

    it "appears in the trip's dropping stops" do
      expect(trip.dropping_stops).to eq([ dropping ])
    end

    it "does not appear among the boarding stops" do
      expect(trip.boarding_stops).not_to include(dropping)
    end
  end

  describe "how a booking reaches it" do
    let(:trip) { create(:trip, :with_stops) }

    it "can be assigned as a booking's dropping stop" do
      booking = build(:booking, trip: trip, dropping_stop: trip.dropping_stops.first)
      expect(booking).to be_valid
    end

    it "cannot be assigned as a booking's boarding stop" do
      expect { build(:booking, boarding_stop: create(:dropping_stop)) }
        .to raise_error(ActiveRecord::AssociationTypeMismatch)
    end
  end
end
