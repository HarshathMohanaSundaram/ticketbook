require "rails_helper"

RSpec.describe TripSeat do
  describe "ticket associations across a cancellation" do
    let(:trip) { create(:trip) }
    let(:seat) { create(:trip_seat, trip: trip, status: "booked") }

    it "exposes the confirmed ticket as current_ticket" do
      ticket = create(:ticket, trip_seat: seat, passenger_name: "Ravi",
                               booking: create(:booking, trip: trip, status: "confirmed"))

      expect(seat.reload.current_ticket).to eq(ticket)
      expect(seat.current_booking).to eq(ticket.booking)
      expect(seat.past_tickets).to be_empty
    end

    it "moves a cancelled booking's ticket into past_tickets" do
      cancelled = create(:booking, trip: trip, status: "cancelled",
                                   cancelled_at: Time.current, refund_paise: 0)
      ticket = create(:ticket, trip_seat: seat, booking: cancelled, passenger_name: "Ravi")

      expect(seat.reload.current_ticket).to be_nil
      expect(seat.past_tickets).to eq([ ticket ])
    end

    it "keeps one current ticket when a released seat is booked again" do
      old_booking = create(:booking, trip: trip, status: "cancelled",
                                     cancelled_at: Time.current, refund_paise: 0)
      create(:ticket, trip_seat: seat, booking: old_booking, passenger_name: "Ravi")

      new_booking = create(:booking, trip: trip, status: "confirmed")
      live = create(:ticket, trip_seat: seat, booking: new_booking, passenger_name: "Meera")

      expect(seat.reload.tickets.count).to eq(2)
      expect(seat.current_ticket).to eq(live)
      expect(seat.past_tickets.map(&:passenger_name)).to eq([ "Ravi" ])
    end

    it "can be preloaded, which a method could not be" do
      create(:ticket, trip_seat: seat, booking: create(:booking, trip: trip, status: "confirmed"))

      loaded = described_class.where(id: seat.id).includes(:current_ticket).first

      expect(loaded.association(:current_ticket)).to be_loaded
    end
  end

  describe "#claimable?" do
    it "is true for an available seat" do
      expect(create(:trip_seat)).to be_claimable
    end

    it "is true for a seat whose hold has expired, before any job runs" do
      hold = create(:hold, expires_at: 1.minute.from_now)
      seat = create(:trip_seat, status: "held", hold: hold, hold_expires_at: hold.expires_at)

      travel_to(hold.expires_at + 1.second) do
        expect(seat).to be_stale_hold
        expect(seat).to be_claimable
      end
    end

    it "is false while a hold is live" do
      hold = create(:hold)
      seat = create(:trip_seat, status: "held", hold: hold, hold_expires_at: hold.expires_at)

      expect(seat).not_to be_claimable
    end

    it "is false for a booked seat" do
      expect(create(:trip_seat, status: "booked")).not_to be_claimable
    end
  end
end
