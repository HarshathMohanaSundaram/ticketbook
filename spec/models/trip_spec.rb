require "rails_helper"

RSpec.describe Trip, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:operator) }
    it { is_expected.to belong_to(:bus) }
    it { is_expected.to belong_to(:origin_city).class_name("City") }
    it { is_expected.to belong_to(:destination_city).class_name("City") }
    it { is_expected.to belong_to(:driver).optional }
    it { is_expected.to belong_to(:relief_driver).class_name("Driver").optional }
    it { is_expected.to have_many(:trip_seats).dependent(:destroy) }
    it { is_expected.to have_many(:trip_stops).dependent(:destroy) }
    it { is_expected.to have_many(:boarding_stops).class_name("BoardingStop") }
    it { is_expected.to have_many(:dropping_stops).class_name("DroppingStop") }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:departs_at) }
    it { is_expected.to validate_presence_of(:arrives_at) }
    it { is_expected.to validate_presence_of(:base_fare_paise) }

    context "when the arrival is before the departure" do
      subject(:trip) { build(:trip, departs_at: 2.days.from_now, arrives_at: 1.day.from_now) }

      it "is invalid" do
        expect(trip).not_to be_valid
      end

      it "explains why" do
        trip.valid?
        expect(trip.errors[:arrives_at]).to include("must be after departure")
      end
    end

    context "when the origin and destination are the same city" do
      # Persisted, so both sides have an id: the validation compares ids, and two
      # unsaved cities would both be nil and skip the check.
      let(:city) { create(:city) }

      subject(:trip) { build(:trip, origin_city: city, destination_city: city) }

      it "is invalid" do
        expect(trip).not_to be_valid
      end
    end

    context "when the driver works for another operator" do
      subject(:trip) { build(:trip, driver: create(:driver)) }

      it "is invalid" do
        expect(trip).not_to be_valid
      end

      it "names the operator the driver should belong to" do
        trip.valid?
        expect(trip.errors[:driver].first).to match(/does not work for/)
      end
    end

    context "when the driver works for the trip's operator" do
      it "is valid" do
        operator = create(:operator)
        trip = build(:trip, operator: operator, bus: create(:bus, operator: operator),
                            driver: create(:driver, operator: operator))
        expect(trip).to be_valid
      end
    end
  end

  describe "#bookable?" do
    context "when departure is comfortably ahead" do
      it "returns true" do
        expect(build(:trip, status: "scheduled", departs_at: 2.hours.from_now)).to be_bookable
      end
    end

    context "when departure is inside the thirty minute cutoff" do
      it "returns false" do
        expect(build(:trip, status: "scheduled", departs_at: 20.minutes.from_now)).not_to be_bookable
      end
    end

    context "when the trip has been cancelled" do
      it "returns false" do
        expect(build(:trip, status: "cancelled", departs_at: 2.days.from_now)).not_to be_bookable
      end
    end

    context "when the trip has departed" do
      it "returns false" do
        expect(build(:trip, status: "departed", departs_at: 2.hours.ago)).not_to be_bookable
      end
    end
  end

  describe "#service_date" do
    it "uses the Indian calendar date rather than the UTC one" do
      # 23:30 IST on the 18th is 18:00 UTC on the 18th; a naive UTC read of a
      # 00:30 IST departure would land on the previous day.
      trip = build(:trip, departs_at: Time.find_zone("Asia/Kolkata").parse("2026-09-19 00:30"))
      expect(trip.service_date).to eq(Date.new(2026, 9, 19))
    end
  end

  describe "#duration_minutes" do
    it "measures the journey in minutes" do
      departs_at = 2.days.from_now
      trip = build(:trip, departs_at: departs_at, arrives_at: departs_at + 6.hours)
      expect(trip.duration_minutes).to eq(360)
    end
  end

  describe "#crew" do
    let(:operator) { create(:operator) }

    context "when a relief driver is rostered" do
      it "lists both drivers" do
        trip = build(:trip, operator: operator, bus: create(:bus, operator: operator),
                            driver: create(:driver, operator: operator),
                            relief_driver: create(:driver, operator: operator))
        expect(trip.crew.size).to eq(2)
      end
    end

    context "when only one driver is rostered" do
      it "lists that driver alone" do
        trip = build(:trip, operator: operator, bus: create(:bus, operator: operator),
                            driver: create(:driver, operator: operator))
        expect(trip.crew.size).to eq(1)
      end
    end

    context "when no driver has been assigned" do
      it "is empty" do
        expect(build(:trip).crew).to be_empty
      end
    end
  end

  describe "#available_seats_count" do
    it "counts only the seats still on sale" do
      trip = create(:trip, :with_seats, seat_count: 3)
      trip.trip_seats.first.update!(status: "booked")

      expect(trip.available_seats_count).to eq(2)
    end
  end
end
