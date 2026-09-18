require "rails_helper"

RSpec.describe Bus, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:operator) }
    it { is_expected.to have_many(:trips).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:bus) }

    it { is_expected.to validate_presence_of(:registration_number) }
    # Case-sensitive: registration numbers are stored uppercase and only ever
    # entered by the operator import, never typed by a passenger.
    it { is_expected.to validate_uniqueness_of(:registration_number) }
    it { is_expected.to validate_inclusion_of(:bus_type).in_array(described_class::BUS_TYPES) }
    it { is_expected.to validate_inclusion_of(:berth_type).in_array(described_class::BERTH_TYPES) }
    it { is_expected.to validate_numericality_of(:seats_total).is_greater_than(0) }

    context "when an amenity code is not one we recognise" do
      subject(:bus) { build(:bus, amenity_codes: %w[wifi helicopter]) }

      it "is invalid" do
        expect(bus).not_to be_valid
      end

      it "names the unknown code" do
        bus.valid?
        expect(bus.errors[:amenity_codes].first).to include("helicopter")
      end
    end

    context "when every amenity code is known" do
      it "is valid" do
        expect(build(:bus, amenity_codes: described_class::AMENITY_CODES)).to be_valid
      end
    end
  end

  describe "#label" do
    context "with an air conditioned sleeper" do
      it "reads as AC Sleeper" do
        expect(build(:bus, bus_type: "ac", berth_type: "sleeper").label).to eq("AC Sleeper")
      end
    end

    context "with a non air conditioned seater" do
      it "reads as Non-AC Seater" do
        expect(build(:bus, bus_type: "non_ac", berth_type: "seater").label).to eq("Non-AC Seater")
      end
    end
  end

  describe "#sleeper?" do
    it "is true for a sleeper" do
      expect(build(:bus, berth_type: "sleeper")).to be_sleeper
    end

    it "is false for a seater" do
      expect(build(:bus, berth_type: "seater")).not_to be_sleeper
    end
  end
end
