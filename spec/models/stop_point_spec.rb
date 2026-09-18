require "rails_helper"

RSpec.describe StopPoint, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:city) }
    it { is_expected.to belong_to(:operator).optional }
    it { is_expected.to have_many(:trip_stops).dependent(:restrict_with_error) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe "#full_name" do
    context "when a landmark is recorded" do
      it "joins the name and the landmark" do
        point = build(:stop_point, name: "Madiwala", landmark: "Near the flyover")
        expect(point.full_name).to eq("Madiwala - Near the flyover")
      end
    end

    context "when there is no landmark" do
      it "returns the name alone, with no trailing dash" do
        expect(build(:stop_point, name: "Koyambedu CMBT", landmark: nil).full_name).to eq("Koyambedu CMBT")
      end
    end
  end

  describe ".for_operator" do
    let(:operator) { create(:operator) }
    let!(:shared) { create(:stop_point, operator: nil) }
    let!(:theirs) { create(:stop_point, operator: operator) }
    let!(:rivals) { create(:stop_point, operator: create(:operator)) }

    it "includes the operator's own points" do
      expect(described_class.for_operator(operator)).to include(theirs)
    end

    it "includes points shared by everyone" do
      expect(described_class.for_operator(operator)).to include(shared)
    end

    it "excludes another operator's points" do
      expect(described_class.for_operator(operator)).not_to include(rivals)
    end
  end
end
