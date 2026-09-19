require "rails_helper"

RSpec.describe TripStop, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:trip) }
    it { is_expected.to belong_to(:stop_point) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:scheduled_at) }
  end

  describe "single table inheritance" do
    it "stores a boarding stop under its own class" do
      expect(create(:boarding_stop).type).to eq("BoardingStop")
    end

    it "stores a dropping stop under its own class" do
      expect(create(:dropping_stop).type).to eq("DroppingStop")
    end

    it "reads a boarding stop back as a BoardingStop" do
      stop = create(:boarding_stop)
      expect(described_class.find(stop.id)).to be_a(BoardingStop)
    end

    it "refuses a type outside the two subclasses" do
      stop = create(:boarding_stop)

      expect { described_class.where(id: stop.id).update_all(type: "Sideways") }
        .to raise_error(ActiveRecord::StatementInvalid, /trip_stops_type_valid/)
    end
  end

  describe "#role" do
    it "reads boarding for a BoardingStop" do
      expect(build(:boarding_stop).role).to eq("boarding")
    end

    it "reads dropping for a DroppingStop" do
      expect(build(:dropping_stop).role).to eq("dropping")
    end
  end

  describe "#scheduled_time" do
    it "renders the time in Indian Standard Time" do
      stop = build(:boarding_stop, scheduled_at: Time.utc(2026, 9, 18, 16, 15))
      expect(stop.scheduled_time).to eq("9:45 PM")
    end
  end

  describe "#label" do
    let(:stop_point) { create(:stop_point, name: "Madiwala Checkpost", landmark: nil) }

    it "combines the place with this trip's timing" do
      stop = build(:boarding_stop, stop_point: stop_point, scheduled_at: Time.utc(2026, 9, 18, 16, 15))
      expect(stop.label).to eq("Madiwala Checkpost (9:45 PM)")
    end

    it "includes the landmark when there is one" do
      point = create(:stop_point, name: "Madiwala", landmark: "Near the flyover")
      stop = build(:boarding_stop, stop_point: point, scheduled_at: Time.utc(2026, 9, 18, 16, 15))

      expect(stop.label).to start_with("Madiwala - Near the flyover")
    end
  end

  describe "one place serving both roles on the same trip" do
    let(:trip) { create(:trip) }
    let(:point) { create(:stop_point) }

    before { create(:boarding_stop, trip: trip, stop_point: point, scheduled_at: trip.departs_at) }

    it "allows the same place as a dropping stop" do
      dropping = build(:dropping_stop, trip: trip, stop_point: point, scheduled_at: trip.arrives_at)
      expect(dropping).to be_valid
    end

    it "refuses the same place twice in the same role" do
      duplicate = build(:boarding_stop, trip: trip, stop_point: point, scheduled_at: trip.departs_at)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
