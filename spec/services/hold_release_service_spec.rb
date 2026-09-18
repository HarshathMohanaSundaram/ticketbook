require "rails_helper"

RSpec.describe HoldReleaseService, type: :service do
  subject(:result) { described_class.call(hold: hold, reason: reason) }

  let(:user) { create(:user) }
  let(:trip) { create(:trip, :with_seats, :with_stops, seat_count: 3, departs_at: 8.hours.from_now) }
  let(:seats) { trip.trip_seats.order(:id).to_a }
  let(:hold) do
    SeatHoldService.call(user: user, trip: trip, seat_ids: seats.first(2).map(&:id)).value
  end
  let(:reason) { :released }

  describe "#call" do
    context "when the hold is active" do
      it "returns a success" do
        expect(result).to be_success
      end

      it "marks the hold released" do
        result
        expect(hold.reload).to be_released
      end

      it "returns every seat to the pool" do
        result
        expect(seats.first(2).map(&:reload)).to all(be_available)
      end

      it "detaches the seats from the hold" do
        result
        expect(seats.first(2).map(&:reload).map(&:hold_id)).to all(be_nil)
      end

      it "clears the copied expiry from the seats" do
        result
        expect(seats.first(2).map(&:reload).map(&:hold_expires_at)).to all(be_nil)
      end

      it "leaves seats belonging to no hold alone" do
        result
        expect(seats.last.reload).to be_available
      end
    end

    context "when the reason is expiry" do
      let(:reason) { :expired }

      it "marks the hold expired rather than released" do
        result
        expect(hold.reload).to be_expired
      end
    end

    context "when the hold was already released" do
      before { described_class.call(hold: hold, reason: :released) }

      it "returns a success" do
        expect(result).to be_success
      end

      it "reports that there was nothing to do" do
        expect(result.meta[:already]).to be(true)
      end

      it "leaves the hold released" do
        result
        expect(hold.reload).to be_released
      end
    end

    context "when the hold was converted into a booking while this ran" do
      let!(:stale_hold) { Hold.find(hold.id) }

      before do
        BookingConfirmationService.call(user: user, hold: hold, passengers: [ { name: "A" }, { name: "B" } ])
      end

      # The caller may hold an object loaded before the confirmation committed.
      # Re-reading under the lock is what stops this overwriting a booked hold.
      it "leaves the hold converted" do
        described_class.call(hold: stale_hold, reason: :expired)
        expect(hold.reload).to be_converted
      end

      it "leaves the seats booked" do
        described_class.call(hold: stale_hold, reason: :expired)
        expect(seats.first(2).map(&:reload)).to all(be_booked)
      end

      it "reports that there was nothing to do" do
        expect(described_class.call(hold: stale_hold, reason: :expired).meta[:already]).to be(true)
      end
    end
  end
end
