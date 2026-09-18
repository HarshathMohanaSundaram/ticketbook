require "rails_helper"

RSpec.describe AvailabilityCache do
  let(:trip) { create(:trip) }

  it "starts at zero for a corridor nobody has touched" do
    expect(described_class.version_for(trip.origin_city_id, trip.destination_city_id, trip.service_date))
      .to eq(0)
  end

  it "increments on touch" do
    expect { described_class.touch!(trip) }
      .to change { described_class.version_for(trip.origin_city_id, trip.destination_city_id, trip.service_date) }
      .from(0).to(1)
  end

  it "scopes the counter to one corridor and one day" do
    described_class.touch!(trip)

    other_day = described_class.version_for(trip.origin_city_id, trip.destination_city_id,
                                            trip.service_date + 1)
    other_corridor = described_class.version_for(trip.destination_city_id, trip.origin_city_id,
                                                 trip.service_date)

    expect(other_day).to eq(0)
    expect(other_corridor).to eq(0)
  end
end
