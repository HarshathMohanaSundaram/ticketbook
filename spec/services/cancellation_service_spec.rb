require "rails_helper"

RSpec.describe CancellationService do
  let(:user) { create(:user) }
  let(:trip) { create(:trip, departs_at: 6.hours.from_now) }

  def booking_for(total_paise: 120_000, seats: 1, departs_at: trip.departs_at, status: "confirmed")
    create(:booking, :with_seats, user: user, trip: trip, total_paise: total_paise,
                                  departs_at: departs_at, status: status, seat_count: seats)
  end

  describe "the refund rule" do
    it "refunds the fare less the flat fifty rupee fee" do
      booking = booking_for(total_paise: 120_000)

      result = described_class.call(booking: booking, actor: user)

      expect(result).to be_success
      expect(booking.reload.refund_paise).to eq(115_000)   # Rs.1200 - Rs.50
    end

    it "never refunds below zero when the fare is under the fee" do
      booking = booking_for(total_paise: 3_000)

      described_class.call(booking: booking, actor: user)

      expect(booking.reload.refund_paise).to eq(0)
    end

    it "records the fee that was actually charged" do
      booking = booking_for(total_paise: 120_000)
      expect(booking.cancellation_fee_paise).to eq(5_000)
    end
  end

  describe "the one hour cutoff" do
    it "allows cancellation with more than an hour to spare" do
      booking = booking_for(departs_at: 6.hours.from_now)

      expect(described_class.call(booking: booking, actor: user)).to be_success
    end

    it "allows cancellation at exactly one hour before departure" do
      departs_at = 3.hours.from_now
      booking = booking_for(departs_at: departs_at)

      travel_to(departs_at - 1.hour) do
        expect(described_class.call(booking: booking, actor: user)).to be_success
      end
    end

    it "refuses cancellation at fifty nine minutes" do
      departs_at = 3.hours.from_now
      booking = booking_for(departs_at: departs_at)

      travel_to(departs_at - 59.minutes) do
        result = described_class.call(booking: booking, actor: user)

        expect(result).to be_failure
        expect(result.error).to eq(:cutoff_passed)
        expect(result.meta[:deadline]).to be_within(1.second).of(departs_at - 1.hour)
      end
    end

    it "refuses cancellation after the bus has left" do
      departs_at = 2.hours.from_now
      booking = booking_for(departs_at: departs_at)

      travel_to(departs_at + 1.minute) do
        expect(described_class.call(booking: booking, actor: user).error).to eq(:cutoff_passed)
      end
    end

    it "writes nothing when it refuses" do
      departs_at = 3.hours.from_now
      booking = booking_for(departs_at: departs_at)

      travel_to(departs_at - 10.minutes) do
        described_class.call(booking: booking, actor: user)
      end

      expect(booking.reload).to be_confirmed
      expect(booking.cancelled_at).to be_nil
      expect(booking.refund_paise).to be_nil
      expect(booking.trip_seats.map(&:status)).to all(eq("booked"))
    end
  end

  describe "what happens to the seats and tickets" do
    it "puts every seat back on sale" do
      booking = booking_for(seats: 3, total_paise: 300_000)

      described_class.call(booking: booking, actor: user)

      expect(booking.trip_seats.map(&:reload).map(&:status)).to all(eq("available"))
    end

    it "keeps the tickets as a record of who was booked" do
      booking = booking_for(seats: 2, total_paise: 200_000)

      expect { described_class.call(booking: booking, actor: user) }
        .not_to change { booking.tickets.count }
    end

    it "leaves a released seat bookable by someone else" do
      booking = booking_for
      seat = booking.trip_seats.first

      described_class.call(booking: booking, actor: user)

      expect(seat.reload).to be_claimable
    end
  end

  describe "idempotency" do
    it "returns the first cancellation instead of refunding twice" do
      booking = booking_for(total_paise: 120_000)

      first = described_class.call(booking: booking, actor: user)
      second = described_class.call(booking: booking.reload, actor: user)

      expect(second).to be_success
      expect(second.meta[:replay]).to be(true)
      expect(booking.reload.refund_paise).to eq(115_000)
      expect(first.value.cancelled_at).to eq(booking.cancelled_at)
    end

    it "does not re-release seats that someone else has since taken" do
      booking = booking_for
      seat = booking.trip_seats.first
      described_class.call(booking: booking, actor: user)

      # The seat is sold again after the cancellation.
      seat.reload.update!(status: "booked")

      described_class.call(booking: booking.reload, actor: user)

      expect(seat.reload).to be_booked
    end
  end

  describe "authorisation" do
    it "refuses a booking that belongs to someone else" do
      booking = booking_for

      result = described_class.call(booking: booking, actor: create(:user))

      expect(result.error).to eq(:forbidden)
      expect(booking.reload).to be_confirmed
    end
  end

  describe "concurrency" do
    self.use_transactional_tests = false

    it "produces one cancellation when two requests arrive together" do
      booking = booking_for(total_paise: 120_000)

      results = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(booking: Booking.find(booking.id), actor: user)
          end
        end
      end.map(&:value)

      expect(results).to all(be_success)
      expect(results.count { |r| r.meta[:replay] }).to eq(1)
      expect(booking.reload.refund_paise).to eq(115_000)
      expect(booking.trip_seats.map(&:reload).map(&:status)).to all(eq("available"))
    end
  end
end
