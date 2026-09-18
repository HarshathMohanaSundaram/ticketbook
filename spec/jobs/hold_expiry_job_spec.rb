require "rails_helper"

RSpec.describe HoldExpiryJob, type: :job do
  subject(:perform) { described_class.perform_now(hold.id) }

  let(:user) { create(:user) }
  let(:trip) { create(:trip, :with_seats, seat_count: 2, departs_at: 8.hours.from_now) }
  let(:hold) do
    SeatHoldService.call(user: user, trip: trip, seat_ids: [ trip.trip_seats.first.id ]).value
  end

  # Ages the hold the way five real minutes would, without waiting: the
  # holds_expire_after_creation constraint refuses a hold that expired before it
  # was created, so created_at has to move too.
  def expire!(a_hold)
    Hold.where(id: a_hold.id).update_all(created_at: 10.minutes.ago, expires_at: 1.second.ago)
    TripSeat.where(hold_id: a_hold.id).update_all(hold_expires_at: 1.second.ago)
    a_hold.reload
  end

  describe "#perform" do
    context "when the hold has expired" do
      before { expire!(hold) }

      it "marks the hold expired" do
        perform
        expect(hold.reload).to be_expired
      end

      it "returns the seat to the pool" do
        perform
        expect(trip.trip_seats.first.reload).to be_available
      end

      it "detaches the seat from the hold" do
        perform
        expect(trip.trip_seats.first.reload.hold_id).to be_nil
      end
    end

    context "when the hold was already converted into a booking" do
      before do
        BookingConfirmationService.call(user: user, hold: hold, passengers: [ { name: "Ravi" } ])
        expire!(hold)
      end

      it "leaves the hold converted" do
        perform
        expect(hold.reload).to be_converted
      end

      it "leaves the seat booked" do
        perform
        expect(trip.trip_seats.first.reload).to be_booked
      end
    end

    context "when the hold was already released" do
      before do
        HoldReleaseService.call(hold: hold, reason: :released)
        expire!(hold)
      end

      it "leaves the hold released" do
        perform
        expect(hold.reload).to be_released
      end
    end

    context "when the job runs before the hold has expired" do
      it "leaves the hold active" do
        perform
        expect(hold.reload).to be_active
      end

      it "keeps the seat held" do
        perform
        expect(trip.trip_seats.first.reload).to be_held
      end

      it "re-enqueues itself for the real expiry time" do
        expect { perform }.to have_enqueued_job(described_class).with(hold.id)
      end
    end

    context "when the hold no longer exists" do
      subject(:perform) { described_class.perform_now(hold.id) }

      before { TripSeat.where(hold_id: hold.id).update_all(hold_id: nil, hold_expires_at: nil, status: "available"); hold.delete }

      it "discards the job rather than retrying forever" do
        expect { perform }.not_to raise_error
      end
    end

    context "when the job is delivered twice" do
      before { expire!(hold) }

      it "does not raise on the second run" do
        perform
        expect { described_class.perform_now(hold.id) }.not_to raise_error
      end

      it "leaves the seat available" do
        perform
        described_class.perform_now(hold.id)
        expect(trip.trip_seats.first.reload).to be_available
      end
    end
  end

  describe "queue" do
    it "runs on the critical queue" do
      expect(described_class.new.queue_name).to eq("critical")
    end
  end
end
