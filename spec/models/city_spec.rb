require "rails_helper"

RSpec.describe City, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:stop_points).dependent(:destroy) }
    it { is_expected.to have_many(:departing_trips).class_name("Trip").dependent(:restrict_with_error) }
    it { is_expected.to have_many(:arriving_trips).class_name("Trip").dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:city) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:state) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:slug) }
  end

  describe "#to_param" do
    it "puts the slug in URLs rather than the id" do
      expect(build(:city, slug: "bangalore").to_param).to eq("bangalore")
    end
  end

  describe ".alphabetical" do
    it "orders cities by name" do
      create(:city, name: "Mysore")
      create(:city, name: "Bangalore")

      expect(described_class.alphabetical.pluck(:name)).to eq([ "Bangalore", "Mysore" ])
    end
  end
end
