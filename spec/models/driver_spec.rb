require "rails_helper"

RSpec.describe Driver, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:operator) }
    it { is_expected.to have_many(:trips).dependent(:nullify) }
    it { is_expected.to have_many(:relief_trips).class_name("Trip").dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:driver) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:licence_number) }
    it { is_expected.to validate_uniqueness_of(:licence_number) }
  end

  describe "#licence_valid_on?" do
    context "when the licence expires in the future" do
      it "returns true" do
        expect(build(:driver, licence_expires_on: 1.year.from_now)).to be_licence_valid_on(Date.current)
      end
    end

    context "when the licence expires today" do
      it "returns true" do
        expect(build(:driver, licence_expires_on: Date.current)).to be_licence_valid_on(Date.current)
      end
    end

    context "when the licence has lapsed" do
      it "returns false" do
        expect(build(:driver, licence_expires_on: 1.day.ago)).not_to be_licence_valid_on(Date.current)
      end
    end

    context "when no expiry is recorded" do
      it "returns true" do
        expect(build(:driver, licence_expires_on: nil)).to be_licence_valid_on(Date.current)
      end
    end
  end

  describe "#masked_phone" do
    context "when a phone number is recorded" do
      it "hides the middle digits" do
        expect(build(:driver, phone: "9876543210").masked_phone).to eq("987xxxxx10")
      end
    end

    context "when no phone number is recorded" do
      it "returns nothing to display" do
        expect(build(:driver, phone: nil).masked_phone).to be_nil
      end
    end
  end

  describe "database constraints" do
    it "refuses a trip whose relief driver is also its main driver" do
      operator = create(:operator)
      driver = create(:driver, operator: operator)
      trip = create(:trip, operator: operator, bus: create(:bus, operator: operator), driver: driver)

      expect { Trip.where(id: trip.id).update_all(relief_driver_id: driver.id) }
        .to raise_error(ActiveRecord::StatementInvalid, /trips_relief_driver_differs/)
    end
  end
end
