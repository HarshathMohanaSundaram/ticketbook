require "rails_helper"

RSpec.describe SeatHoldService, type: :service do
  subject(:result) { described_class.call(user: user, trip: trip, seat_ids: seat_ids) }

  let(:user) { create(:user) }
  let(:trip) { create(:trip, :with_seats, seat_count: 6, departs_at: 8.hours.from_now) }
  let(:seats) { trip.trip_seats.order(:id).to_a }
  let(:seat_ids) { [ seats.first.id ] }

  describe "#call" do
    context "when the seats are available" do
      let(:seat_ids) { seats.first(2).map(&:id) }

      it "returns a success" do
        expect(result).to be_success
      end

      it "creates one hold" do
        expect { result }.to change(Hold, :count).by(1)
      end

      it "expires the hold five minutes out" do
        expect(result.value.expires_at).to be_within(2.seconds).of(Hold::HOLD_WINDOW.from_now)
      end

      it "attaches both seats to the hold" do
        expect(result.value.trip_seats.count).to eq(2)
      end

      it "marks the seats as held" do
        result
        expect(seats.first(2).map(&:reload)).to all(be_held)
      end

      it "copies the expiry onto each seat" do
        result
        expect(seats.first.reload.hold_expires_at).to be_within(2.seconds).of(result.value.expires_at)
      end

      it "totals the price of the seats held" do
        expect(result.value.total_paise).to eq(seats.first(2).sum(&:price_paise))
      end

      it "leaves the unselected seats available" do
        result
        expect(seats.last(4).map(&:reload)).to all(be_available)
      end
    end

    context "when another user is already holding the seat" do
      before { described_class.call(user: create(:user), trip: trip, seat_ids: [ seats.first.id ]) }

      include_examples "a refused operation", :seats_taken

      it "names the seat that was taken" do
        expect(result.meta[:seat_numbers]).to eq([ seats.first.seat_number ])
      end

      it "creates no second hold for this user" do
        result
        expect(user.holds).to be_empty
      end
    end

    context "when the seat is already booked" do
      before { seats.first.update!(status: "booked") }

      include_examples "a refused operation", :seats_taken
    end

    context "when only one seat of several is unavailable" do
      let(:seat_ids) { seats.first(2).map(&:id) }

      before { described_class.call(user: create(:user), trip: trip, seat_ids: [ seats.first.id ]) }

      include_examples "a refused operation", :seats_taken

      it "leaves the still-free seat available" do
        result
        expect(seats.second.reload).to be_available
      end
    end

    context "when the hold has expired but no job has run" do
      let(:other_user) { create(:user) }

      before { travel_to(described_class.call(user: other_user, trip: trip, seat_ids: seat_ids).value.expires_at + 1.second) }

      after { travel_back }

      it "still reads as held in the database" do
        expect(seats.first.reload).to be_held
      end

      it "returns a success for the next user" do
        expect(result).to be_success
      end

      it "transfers the seat to the new hold" do
        new_hold = result.value
        expect(seats.first.reload.hold_id).to eq(new_hold.id)
      end

      # The stale hold belongs to someone else, so this service only takes the
      # seat away from it. Tidying the hold row itself is HoldExpiryJob's job.
      it "leaves the stale hold owning no seats" do
        result
        expect(other_user.holds.first.trip_seats).to be_empty
      end
    end

    context "when the user already holds other seats on the trip" do
      let(:seat_ids) { seats.last(2).map(&:id) }
      let!(:previous) { described_class.call(user: user, trip: trip, seat_ids: seats.first(2).map(&:id)).value }

      it "returns a success" do
        expect(result).to be_success
      end

      it "releases the previous hold" do
        result
        expect(previous.reload).to be_released
      end

      it "frees the previously held seats" do
        result
        expect(seats.first(2).map(&:reload)).to all(be_available)
      end

      it "leaves the user with a single live hold" do
        result
        expect(user.holds.live.count).to eq(1)
      end
    end

    context "when the new selection overlaps the user's own hold" do
      let(:seat_ids) { [ seats.second.id, seats.third.id ] }

      before { described_class.call(user: user, trip: trip, seat_ids: seats.first(2).map(&:id)) }

      it "returns a success rather than reporting the user's own seat as taken" do
        expect(result).to be_success
      end

      it "keeps the overlapping seat held" do
        result
        expect(seats.second.reload).to be_held
      end

      it "releases the seat that was dropped" do
        result
        expect(seats.first.reload).to be_available
      end
    end

    context "when the new selection fails after the user already holds seats" do
      let(:seat_ids) { [ seats.second.id, seats.third.id ] }
      let!(:previous) { described_class.call(user: user, trip: trip, seat_ids: seats.first(2).map(&:id)).value }

      before { described_class.call(user: create(:user), trip: trip, seat_ids: [ seats.third.id ]) }

      include_examples "a refused operation", :seats_taken

      # An early return inside a transaction commits in Rails, so a refusal after
      # a write would silently destroy the hold the user already had.
      it "leaves the existing hold active" do
        result
        expect(previous.reload).to be_active
      end

      it "leaves the existing seats held" do
        result
        expect(seats.first(2).map(&:reload)).to all(be_held)
      end
    end

    context "when more than the maximum number of seats is requested" do
      let(:trip) { create(:trip, :with_seats, seat_count: Hold::MAX_SEATS + 1, departs_at: 8.hours.from_now) }
      let(:seat_ids) { seats.map(&:id) }

      include_examples "a refused operation", :too_many_seats
      include_examples "an operation that writes nothing", Hold

      it "reports the limit" do
        expect(result.meta[:limit]).to eq(Hold::MAX_SEATS)
      end
    end

    context "when no seat is selected" do
      let(:seat_ids) { [] }

      include_examples "a refused operation", :no_seats_selected
      include_examples "an operation that writes nothing", Hold
    end

    context "when the seat belongs to another trip" do
      let(:seat_ids) { [ create(:trip, :with_seats, seat_count: 1).trip_seats.first.id ] }

      include_examples "a refused operation", :seat_not_found
      include_examples "an operation that writes nothing", Hold
    end

    context "when the trip is too close to departure" do
      let(:trip) { create(:trip, :with_seats, seat_count: 1, departs_at: 10.minutes.from_now) }

      include_examples "a refused operation", :trip_not_bookable
      include_examples "an operation that writes nothing", Hold
    end

    # The requirement the brief calls concurrency-critical: no two users may hold
    # the same seat. Real threads on real connections, because the mechanism under
    # test is a Postgres row lock -- a mocked model would prove nothing.
    context "when twelve users request the same seat at once", :concurrency do
      # Each thread takes its own connection and cannot see another connection's
      # open transaction, so the usual rollback-per-example wrapper would hide the
      # rows this group creates.
      self.use_transactional_tests = false

      # let!, not let: every record must exist before a thread starts. RSpec's let
      # memoisation is not thread-safe, so a lazily-evaluated factory referenced
      # from inside twelve threads has twelve of them racing to create it.
      let!(:contended_trip) { create(:trip, :with_seats, seat_count: 1, departs_at: 8.hours.from_now) }
      let!(:contended_seat) { contended_trip.trip_seats.first }
      let!(:racers) { create_list(:user, 12) }

      let(:results) do
        trip_id = contended_trip.id
        seat_id = contended_seat.id

        racers.map do |racer|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(user: racer, trip: Trip.find(trip_id), seat_ids: [ seat_id ])
            end
          end
        end.map(&:value)
      end

      it "lets exactly one of them win" do
        expect(results.count(&:success?)).to eq(1)
      end

      it "refuses the other eleven" do
        expect(results.count(&:failure?)).to eq(11)
      end

      it "refuses them because the seat was taken" do
        expect(results.select(&:failure?).map(&:error).uniq).to eq([ :seats_taken ])
      end

      it "creates exactly one hold" do
        results
        expect(Hold.count).to eq(1)
      end

      it "leaves the seat held by the winner" do
        winner = results.find(&:success?).value
        expect(contended_seat.reload.hold_id).to eq(winner.id)
      end
    end

    context "when two users request the same pair of seats in opposite orders", :concurrency do
      self.use_transactional_tests = false

      let!(:pair_trip) { create(:trip, :with_seats, seat_count: 2, departs_at: 8.hours.from_now) }
      let!(:pair) { pair_trip.trip_seats.order(:id).to_a }
      let!(:racers) { create_list(:user, 6) }

      let(:results) do
        trip_id = pair_trip.id
        ids = pair.map(&:id)

        [ ids, ids.reverse, ids, ids.reverse, ids, ids.reverse ].each_with_index.map do |ordered, index|
          racer = racers[index]
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(user: racer, trip: Trip.find(trip_id), seat_ids: ordered)
            end
          end
        end.map(&:value)
      end

      # Locking ORDER BY id is what turns a deadlock into a queue.
      it "deadlocks none of them" do
        expect(results.map(&:error).compact.uniq).not_to include(:deadlock)
      end

      it "lets exactly one of them win" do
        expect(results.count(&:success?)).to eq(1)
      end

      it "creates exactly one hold" do
        results
        expect(Hold.count).to eq(1)
      end
    end

    context "when the same seat is submitted twice" do
      let(:seat_ids) { [ seats.first.id, seats.first.id ] }

      it "returns a success" do
        expect(result).to be_success
      end

      it "charges for the seat once" do
        expect(result.value.total_paise).to eq(seats.first.price_paise)
      end
    end
  end
end
