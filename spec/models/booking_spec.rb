require "rails_helper"

RSpec.describe Booking, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:trip) }
    it { is_expected.to belong_to(:hold).optional }
    it { is_expected.to belong_to(:boarding_stop).class_name("BoardingStop").optional }
    it { is_expected.to belong_to(:dropping_stop).class_name("DroppingStop").optional }
    it { is_expected.to belong_to(:rescheduled_from).class_name("Booking").optional }
    it { is_expected.to have_many(:tickets).dependent(:destroy) }
    it { is_expected.to have_many(:trip_seats).through(:tickets) }
  end

  describe "validations" do
    subject { build(:booking) }

    it { is_expected.to validate_presence_of(:pnr) }
    # Case-sensitive: PNRs are generated uppercase and only ever appear in URLs
    # the app itself produced.
    it { is_expected.to validate_uniqueness_of(:pnr) }
    it { is_expected.to validate_numericality_of(:total_paise).is_greater_than_or_equal_to(0) }
  end

  describe "#to_param" do
    it "addresses the booking by PNR rather than id" do
      booking = build(:booking, pnr: "TB7K2M9Q")
      expect(booking.to_param).to eq("TB7K2M9Q")
    end
  end

  describe ".generate_pnr" do
    it "is eight characters long" do
      expect(described_class.generate_pnr.length).to eq(8)
    end

    it "uses no vowels, so it cannot spell anything" do
      expect(described_class.generate_pnr).not_to match(/[AEIOU]/)
    end

    it "excludes characters that are misread aloud" do
      expect(described_class.generate_pnr).not_to match(/[01OI]/)
    end
  end

  describe "#cancellable?" do
    let(:departs_at) { Time.zone.parse("2026-09-20 21:00") }
    let(:booking) { build(:booking, status: "confirmed", departs_at: departs_at) }

    context "when there are hours to spare" do
      it "returns true" do
        expect(booking.cancellable?(departs_at - 6.hours)).to be(true)
      end
    end

    context "when there is exactly one hour left" do
      it "returns true, because the brief says at least one hour" do
        expect(booking.cancellable?(departs_at - 1.hour)).to be(true)
      end
    end

    context "when there are fifty nine minutes left" do
      it "returns false" do
        expect(booking.cancellable?(departs_at - 59.minutes)).to be(false)
      end
    end

    context "when the bus has already left" do
      it "returns false" do
        expect(booking.cancellable?(departs_at + 1.minute)).to be(false)
      end
    end

    context "when the booking is already cancelled" do
      let(:booking) { build(:booking, status: "cancelled", departs_at: departs_at) }

      it "returns false regardless of the time" do
        expect(booking.cancellable?(departs_at - 6.hours)).to be(false)
      end
    end
  end

  describe "#projected_refund_paise" do
    context "when the fare is well above the fee" do
      it "returns the fare less fifty rupees" do
        expect(build(:booking, total_paise: 120_000).projected_refund_paise).to eq(115_000)
      end
    end

    context "when the fare is below the fee" do
      it "returns zero rather than a negative refund" do
        expect(build(:booking, total_paise: 3_000).projected_refund_paise).to eq(0)
      end
    end

    context "when the fare is exactly the fee" do
      it "returns zero" do
        expect(build(:booking, total_paise: 5_000).projected_refund_paise).to eq(0)
      end
    end
  end

  describe "#cancellation_fee_paise" do
    context "when the fare is above the fee" do
      it "returns the flat fifty rupees" do
        expect(build(:booking, total_paise: 120_000).cancellation_fee_paise).to eq(5_000)
      end
    end

    context "when the fare is below the fee" do
      it "never charges more than the fare" do
        expect(build(:booking, total_paise: 3_000).cancellation_fee_paise).to eq(3_000)
      end
    end
  end

  describe "#cancellation_deadline" do
    it "is one hour before departure" do
      departs_at = Time.zone.parse("2026-09-20 21:00")
      expect(build(:booking, departs_at: departs_at).cancellation_deadline).to eq(departs_at - 1.hour)
    end
  end

  describe "#fare_difference_paise" do
    context "when the booking replaced a cheaper one" do
      it "returns what the passenger owes" do
        original = create(:booking, total_paise: 90_000)
        successor = build(:booking, total_paise: 150_000, rescheduled_from: original)

        expect(successor.fare_difference_paise).to eq(60_000)
      end
    end

    context "when the booking replaced a dearer one" do
      it "returns a negative difference" do
        original = create(:booking, total_paise: 150_000)
        successor = build(:booking, total_paise: 90_000, rescheduled_from: original)

        expect(successor.fare_difference_paise).to eq(-60_000)
      end
    end

    context "when the booking replaced nothing" do
      it "returns zero" do
        expect(build(:booking).fare_difference_paise).to eq(0)
      end
    end
  end

  describe "#stops_belong_to_this_trip" do
    let(:trip) { create(:trip, :with_stops) }
    let(:other_trip) { create(:trip, :with_stops) }

    context "when the boarding point is on the booked trip" do
      it "is valid" do
        booking = build(:booking, trip: trip, boarding_stop: trip.boarding_stops.first)
        expect(booking).to be_valid
      end
    end

    context "when the boarding point belongs to another trip" do
      subject(:booking) { build(:booking, trip: trip, boarding_stop: other_trip.boarding_stops.first) }

      it "is invalid" do
        expect(booking).not_to be_valid
      end

      it "explains which stop is wrong" do
        booking.valid?
        expect(booking.errors[:boarding_stop]).to include("is not a stop on this trip")
      end
    end
  end

  describe "scopes" do
    describe ".upcoming" do
      it "includes a confirmed booking in the future" do
        booking = create(:booking, status: "confirmed", departs_at: 2.days.from_now)
        expect(described_class.upcoming).to include(booking)
      end

      it "excludes a cancelled booking" do
        booking = create(:booking, status: "cancelled", departs_at: 2.days.from_now,
                                   cancelled_at: Time.current, refund_paise: 0)
        expect(described_class.upcoming).not_to include(booking)
      end

      it "excludes a booking that has departed" do
        booking = create(:booking, status: "confirmed", departs_at: 2.hours.ago)
        expect(described_class.upcoming).not_to include(booking)
      end
    end
  end
end
