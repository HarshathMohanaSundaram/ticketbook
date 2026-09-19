# BoardingStop and DroppingStop differ only in which role they play, so the
# behaviour they share is asserted once and included by both.
RSpec.shared_examples "a trip stop subclass" do |factory_name, expected_role|
  subject(:stop) { build(factory_name) }

  it "inherits from TripStop" do
    expect(described_class.superclass).to eq(TripStop)
  end

  it "reads its role from the class name" do
    expect(stop.role).to eq(expected_role)
  end

  it "stores its class in the type column" do
    expect(create(factory_name).type).to eq(described_class.name)
  end

  it "is found by its own class, not the base one" do
    record = create(factory_name)
    expect(described_class.find(record.id)).to be_a(described_class)
  end

  it "is excluded from the sibling subclass's scope" do
    record = create(factory_name)
    sibling = described_class == BoardingStop ? DroppingStop : BoardingStop

    expect(sibling.where(id: record.id)).to be_empty
  end

  describe ".for_trip" do
    it "returns this trip's stops in order" do
      trip = create(:trip)
      second = create(factory_name, trip: trip, position: 1)
      first = create(factory_name, trip: trip, position: 0)

      expect(described_class.for_trip(trip)).to eq([ first, second ])
    end

    it "excludes another trip's stops" do
      trip = create(:trip)
      create(factory_name, trip: create(:trip))

      expect(described_class.for_trip(trip)).to be_empty
    end
  end
end
