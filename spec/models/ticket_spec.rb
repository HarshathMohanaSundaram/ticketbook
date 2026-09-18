require "rails_helper"

RSpec.describe Ticket, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:booking) }
    it { is_expected.to belong_to(:trip_seat) }
  end

  describe "validations" do
    subject { build(:ticket) }

    it { is_expected.to validate_presence_of(:passenger_name) }
    it { is_expected.to validate_numericality_of(:price_paise).is_greater_than_or_equal_to(0) }

    context "when the age is outside a plausible range" do
      it "rejects zero" do
        expect(build(:ticket, passenger_age: 0)).not_to be_valid
      end

      it "rejects an implausible age" do
        expect(build(:ticket, passenger_age: 130)).not_to be_valid
      end

      it "allows a blank age" do
        expect(build(:ticket, passenger_age: nil)).to be_valid
      end
    end

    context "when the same seat is ticketed twice on one booking" do
      let(:booking) { create(:booking) }
      let(:seat) { create(:trip_seat, trip: booking.trip) }

      before { create(:ticket, booking: booking, trip_seat: seat) }

      it "is invalid" do
        expect(build(:ticket, booking: booking, trip_seat: seat)).not_to be_valid
      end
    end
  end

  describe "delegation" do
    it "reads the seat number from the seat" do
      ticket = build(:ticket, trip_seat: build(:trip_seat, seat_number: "L7"))
      expect(ticket.seat_number).to eq("L7")
    end

    it "reads the berth type from the seat" do
      ticket = build(:ticket, trip_seat: build(:trip_seat, berth_type: "sleeper"))
      expect(ticket.berth_type).to eq("sleeper")
    end
  end
end
