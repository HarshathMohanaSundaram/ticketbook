require "rails_helper"

RSpec.describe TripSeat, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:trip) }
    it { is_expected.to belong_to(:hold).optional }
    it { is_expected.to have_many(:tickets).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:bookings).through(:tickets) }
    it { is_expected.to have_one(:current_ticket).class_name("Ticket") }
  end

  describe "validations" do
    subject { build(:trip_seat) }

    it { is_expected.to validate_presence_of(:seat_number) }
    it { is_expected.to validate_numericality_of(:price_paise).is_greater_than_or_equal_to(0) }

    context "when the same seat number is used twice on one trip" do
      let(:trip) { create(:trip) }

      before { create(:trip_seat, trip: trip, seat_number: "L1") }

      it "is invalid" do
        expect(build(:trip_seat, trip: trip, seat_number: "L1")).not_to be_valid
      end

      it "is refused by the database even when validations are skipped" do
        duplicate = build(:trip_seat, trip: trip, seat_number: "L1")

        expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "when the same seat number is used on a different trip" do
      before { create(:trip_seat, trip: create(:trip), seat_number: "L1") }

      it "is valid" do
        expect(build(:trip_seat, trip: create(:trip), seat_number: "L1")).to be_valid
      end
    end
  end

  describe "the seat lifecycle" do
    context "when newly created" do
      it "starts available" do
        expect(create(:trip_seat)).to be_available
      end
    end

    context "when a hold is placed" do
      let(:hold) { create(:hold) }
      let(:seat) { create(:trip_seat) }

      it "moves to held" do
        seat.assign_attributes(hold: hold, hold_expires_at: hold.expires_at)
        seat.place_hold!
        expect(seat.reload).to be_held
      end
    end

    context "when confirming a seat that was never held" do
      it "refuses the transition" do
        expect { create(:trip_seat).confirm! }.to raise_error(AASM::InvalidTransition)
      end
    end

    context "when booking a seat directly, as rescheduling does" do
      it "moves an available seat to booked" do
        seat = create(:trip_seat)
        seat.book!
        expect(seat.reload).to be_booked
      end

      it "refuses a seat that is already held" do
        hold = create(:hold)
        seat = create(:trip_seat, status: "held", hold: hold, hold_expires_at: hold.expires_at)

        expect { seat.book! }.to raise_error(AASM::InvalidTransition)
      end
    end

    context "when releasing" do
      it "returns a booked seat to available" do
        seat = create(:trip_seat, status: "booked")
        seat.release!
        expect(seat.reload).to be_available
      end
    end
  end

  describe "#claimable?" do
    context "when the seat is available" do
      it "is true" do
        expect(create(:trip_seat)).to be_claimable
      end
    end

    context "when a live hold owns the seat" do
      let(:hold) { create(:hold) }

      it "is false" do
        seat = create(:trip_seat, status: "held", hold: hold, hold_expires_at: hold.expires_at)
        expect(seat).not_to be_claimable
      end
    end

    context "when the hold has expired but no job has released it" do
      let(:hold) { create(:hold, expires_at: 1.minute.from_now) }
      let(:seat) { create(:trip_seat, status: "held", hold: hold, hold_expires_at: hold.expires_at) }

      it "reports a stale hold" do
        travel_to(hold.expires_at + 1.second) { expect(seat).to be_stale_hold }
      end

      it "is claimable, so a dead Sidekiq cannot wedge the seat" do
        travel_to(hold.expires_at + 1.second) { expect(seat).to be_claimable }
      end
    end

    context "when the seat is booked" do
      it "is false" do
        expect(create(:trip_seat, status: "booked")).not_to be_claimable
      end
    end
  end

  describe "tickets across a cancellation" do
    let(:trip) { create(:trip) }
    let(:seat) { create(:trip_seat, trip: trip, status: "booked") }

    context "while the booking is confirmed" do
      let!(:ticket) do
        create(:ticket, trip_seat: seat, passenger_name: "Ravi",
                        booking: create(:booking, trip: trip, status: "confirmed"))
      end

      it "exposes the live ticket" do
        expect(seat.reload.current_ticket).to eq(ticket)
      end

      it "exposes the live booking" do
        expect(seat.reload.current_booking).to eq(ticket.booking)
      end

      it "has no past tickets" do
        expect(seat.reload.past_tickets).to be_empty
      end
    end

    context "after the booking is cancelled" do
      let!(:ticket) do
        create(:ticket, trip_seat: seat,
                        booking: create(:booking, trip: trip, status: "cancelled",
                                                  cancelled_at: Time.current, refund_paise: 0))
      end

      it "has no live ticket" do
        expect(seat.reload.current_ticket).to be_nil
      end

      it "keeps the ticket as history" do
        expect(seat.reload.past_tickets).to eq([ ticket ])
      end
    end

    context "when the freed seat is booked again" do
      before do
        create(:ticket, trip_seat: seat, passenger_name: "Ravi",
                        booking: create(:booking, trip: trip, status: "cancelled",
                                                  cancelled_at: Time.current, refund_paise: 0))
      end

      let!(:live_ticket) do
        create(:ticket, trip_seat: seat, passenger_name: "Meera",
                        booking: create(:booking, trip: trip, status: "confirmed"))
      end

      it "holds two tickets in total" do
        expect(seat.reload.tickets.count).to eq(2)
      end

      it "reports the new one as current" do
        expect(seat.reload.current_ticket).to eq(live_ticket)
      end

      it "keeps the cancelled one in history" do
        expect(seat.reload.past_tickets.map(&:passenger_name)).to eq([ "Ravi" ])
      end
    end

    context "when preloading" do
      before do
        create(:ticket, trip_seat: seat, booking: create(:booking, trip: trip, status: "confirmed"))
      end

      it "loads the current ticket in one go, which a method could not" do
        loaded = described_class.where(id: seat.id).includes(:current_ticket).first
        expect(loaded.association(:current_ticket)).to be_loaded
      end
    end
  end

  describe ".available_counts_by_trip" do
    let(:trip) { create(:trip, :with_seats, seat_count: 3) }

    before { trip.trip_seats.first.update!(status: "booked") }

    it "counts only the seats still on sale" do
      expect(described_class.available_counts_by_trip([ trip.id ])[trip.id]).to eq(2)
    end

    it "answers for a whole page in one query" do
      other = create(:trip, :with_seats, seat_count: 2)
      expect(described_class.available_counts_by_trip([ trip.id, other.id ]).keys).to contain_exactly(trip.id, other.id)
    end
  end

  describe "database constraints" do
    it "refuses a held seat that carries no hold" do
      seat = create(:trip_seat)

      expect { described_class.where(id: seat.id).update_all(status: "held") }
        .to raise_error(ActiveRecord::StatementInvalid, /trip_seats_held_has_a_hold/)
    end

    it "refuses a status outside the lifecycle" do
      seat = create(:trip_seat)

      expect { described_class.where(id: seat.id).update_all(status: "sold") }
        .to raise_error(ActiveRecord::StatementInvalid, /trip_seats_status_valid/)
    end
  end
end
