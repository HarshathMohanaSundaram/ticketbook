require "rails_helper"

RSpec.describe CancellationService, type: :service do
  subject(:result) { described_class.call(booking: booking, actor: actor) }

  let(:user) { create(:user) }
  let(:actor) { user }
  let(:trip) { create(:trip, departs_at: 6.hours.from_now) }
  let(:total_paise) { 120_000 }
  let(:seat_count) { 1 }
  let(:booking) do
    create(:booking, :with_seats, user: user, trip: trip, total_paise: total_paise,
                                  departs_at: trip.departs_at, seat_count: seat_count)
  end

  describe "#call" do
    context "when the booking can still be cancelled" do
      it "returns a success" do
        expect(result).to be_success
      end

      it "marks the booking cancelled" do
        result
        expect(booking.reload).to be_cancelled
      end

      it "records when it was cancelled" do
        result
        expect(booking.reload.cancelled_at).to be_present
      end

      it "refunds the fare less the flat fifty rupee fee" do
        result
        expect(booking.reload.refund_paise).to eq(115_000)
      end

      it "bumps the corridor's cache version" do
        expect { result }
          .to change { AvailabilityCache.version_for(trip.origin_city_id, trip.destination_city_id, trip.service_date) }
          .by(1)
      end
    end

    context "when the fare is smaller than the cancellation fee" do
      let(:total_paise) { 3_000 }

      it "refunds nothing rather than a negative amount" do
        result
        expect(booking.reload.refund_paise).to eq(0)
      end

      it "charges no more than the fare" do
        expect(booking.cancellation_fee_paise).to eq(3_000)
      end
    end

    context "when there is exactly one hour before departure" do
      subject(:result) { described_class.call(booking: booking, actor: actor, at: trip.departs_at - 1.hour) }

      it "allows the cancellation, because the brief says at least one hour" do
        expect(result).to be_success
      end
    end

    context "when there are fifty nine minutes before departure" do
      subject(:result) { described_class.call(booking: booking, actor: actor, at: trip.departs_at - 59.minutes) }

      include_examples "a refused operation", :cutoff_passed

      it "reports the deadline that has passed" do
        expect(result.meta[:deadline]).to be_within(1.second).of(trip.departs_at - 1.hour)
      end

      it "leaves the booking confirmed" do
        result
        expect(booking.reload).to be_confirmed
      end

      it "records no cancellation time" do
        result
        expect(booking.reload.cancelled_at).to be_nil
      end

      it "records no refund" do
        result
        expect(booking.reload.refund_paise).to be_nil
      end

      it "leaves the seats booked" do
        result
        expect(booking.trip_seats.map(&:reload)).to all(be_booked)
      end
    end

    context "when the bus has already left" do
      subject(:result) { described_class.call(booking: booking, actor: actor, at: trip.departs_at + 1.minute) }

      include_examples "a refused operation", :cutoff_passed
    end

    context "with several seats on the booking" do
      let(:seat_count) { 3 }
      let(:total_paise) { 300_000 }

      it "returns every seat to the pool" do
        result
        expect(booking.trip_seats.map(&:reload)).to all(be_available)
      end

      it "makes each seat claimable again" do
        result
        expect(booking.trip_seats.map(&:reload)).to all(be_claimable)
      end

      it "keeps the tickets as a record of who was booked" do
        expect { result }.not_to change { booking.tickets.count }
      end

      it "moves the tickets into the seats' history" do
        result
        expect(booking.trip_seats.first.reload.past_tickets).not_to be_empty
      end

      it "leaves no seat claiming a live ticket" do
        result
        expect(booking.trip_seats.map(&:reload).map(&:current_ticket)).to all(be_nil)
      end
    end

    context "when the booking has already been cancelled" do
      before { described_class.call(booking: booking, actor: actor) }

      include_examples "a replayed operation"

      it "does not refund a second time" do
        result
        expect(booking.reload.refund_paise).to eq(115_000)
      end

      it "keeps the original cancellation time" do
        original = booking.reload.cancelled_at
        result
        expect(booking.reload.cancelled_at).to eq(original)
      end
    end

    context "when a seat was sold again after the cancellation" do
      before do
        described_class.call(booking: booking, actor: actor)
        booking.trip_seats.first.reload.update!(status: "booked")
      end

      it "does not release the seat out from under its new owner" do
        described_class.call(booking: booking.reload, actor: actor)
        expect(booking.trip_seats.first.reload).to be_booked
      end
    end

    context "when the booking belongs to someone else" do
      let(:actor) { create(:user) }

      include_examples "a refused operation", :forbidden

      it "leaves the booking confirmed" do
        result
        expect(booking.reload).to be_confirmed
      end
    end

    context "when two cancellations arrive at once", :concurrency do
      self.use_transactional_tests = false

      let!(:target) { booking }

      let(:results) do
        booking_id = target.id
        user_id = user.id

        2.times.map do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(booking: Booking.find(booking_id), actor: User.find(user_id))
            end
          end
        end.map(&:value)
      end

      it "succeeds for both requests" do
        expect(results).to all(be_success)
      end

      it "treats exactly one of them as a replay" do
        expect(results.count { |r| r.meta[:replay] }).to eq(1)
      end

      it "refunds only once" do
        results
        expect(target.reload.refund_paise).to eq(115_000)
      end

      it "releases the seats once" do
        results
        expect(target.trip_seats.map(&:reload)).to all(be_available)
      end
    end
  end
end
