require "rails_helper"

RSpec.describe TripManagementJob, type: :job do
  subject(:perform) { described_class.perform_now }

  describe "#perform" do
    context "when a hold has expired but its job never ran" do
      let(:user) { create(:user) }
      let(:trip) { create(:trip, :with_seats, seat_count: 2, departs_at: 8.hours.from_now) }
      let!(:hold) do
        SeatHoldService.call(user: user, trip: trip, seat_ids: [ trip.trip_seats.first.id ]).value.tap do |h|
          Hold.where(id: h.id).update_all(created_at: 10.minutes.ago, expires_at: 1.second.ago)
          TripSeat.where(hold_id: h.id).update_all(hold_expires_at: 1.second.ago)
        end
      end

      it "counts the hold it swept" do
        expect(perform[:release_expired_holds]).to eq(1)
      end

      it "enqueues an expiry job for it" do
        expect { perform }.to have_enqueued_job(HoldExpiryJob).with(hold.id)
      end
    end

    context "when no hold has expired" do
      let(:user) { create(:user) }
      let(:trip) { create(:trip, :with_seats, seat_count: 2, departs_at: 8.hours.from_now) }

      before { SeatHoldService.call(user: user, trip: trip, seat_ids: [ trip.trip_seats.first.id ]) }

      it "sweeps nothing" do
        expect(perform[:release_expired_holds]).to eq(0)
      end

      it "enqueues no expiry job" do
        expect { perform }.not_to have_enqueued_job(HoldExpiryJob)
      end
    end

    context "when a trip has departed but still reads as scheduled" do
      let!(:departed) { create(:trip, departs_at: 3.hours.from_now, arrives_at: 9.hours.from_now) }

      around { |example| travel_to(departed.departs_at + 1.minute) { example.run } }

      it "counts the trip it marked" do
        expect(perform[:mark_departed_trips]).to eq(1)
      end

      it "marks the trip departed" do
        perform
        expect(departed.reload).to be_departed
      end

      it "bumps the corridor's cache version" do
        expect { perform }
          .to change { AvailabilityCache.version_for(departed.origin_city_id, departed.destination_city_id, departed.service_date) }
          .by(1)
      end
    end

    context "when every trip is still in the future" do
      let!(:upcoming) { create(:trip, departs_at: 2.days.from_now) }

      it "marks nothing" do
        expect(perform[:mark_departed_trips]).to eq(0)
      end

      it "leaves the trip scheduled" do
        perform
        expect(upcoming.reload).to be_scheduled
      end
    end

    context "when one task raises" do
      before { allow(Hold).to receive(:expirable).and_raise(ActiveRecord::StatementInvalid, "boom") }

      it "records the failure for that task" do
        expect(perform[:release_expired_holds]).to eq(:failed)
      end

      it "still runs the other task" do
        expect(perform).to have_key(:mark_departed_trips)
      end

      it "does not raise" do
        expect { perform }.not_to raise_error
      end
    end
  end

  describe "queue" do
    it "runs on the critical queue" do
      expect(described_class.new.queue_name).to eq("critical")
    end
  end
end
