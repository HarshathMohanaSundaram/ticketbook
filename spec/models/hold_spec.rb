require "rails_helper"

RSpec.describe Hold, type: :model do
  # Ages a hold past its window. created_at has to move too: the
  # holds_expire_after_creation constraint refuses a hold that expired before it
  # existed, which is exactly the shape of a naive "set expires_at to the past".
  def age_past_expiry(hold)
    described_class.where(id: hold.id)
                   .update_all(created_at: 10.minutes.ago, expires_at: 1.second.ago)
    hold.reload
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:trip) }
    it { is_expected.to have_many(:trip_seats).dependent(:nullify) }
    it { is_expected.to have_one(:booking).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:expires_at) }
  end

  describe "constants" do
    it "holds seats for five minutes" do
      expect(described_class::HOLD_WINDOW).to eq(5.minutes)
    end

    it "allows at most six seats" do
      expect(described_class::MAX_SEATS).to eq(6)
    end
  end

  describe "#live?" do
    context "when the hold is active and inside its window" do
      it "returns true" do
        expect(build(:hold, status: "active", expires_at: 2.minutes.from_now)).to be_live
      end
    end

    context "when the window has passed" do
      it "returns false" do
        expect(build(:hold, status: "active", expires_at: 1.second.ago)).not_to be_live
      end
    end

    context "when the hold was converted" do
      it "returns false even inside the window" do
        expect(build(:hold, status: "converted", expires_at: 2.minutes.from_now)).not_to be_live
      end
    end

    context "when the hold was released" do
      it "returns false" do
        expect(build(:hold, status: "released", expires_at: 2.minutes.from_now)).not_to be_live
      end
    end
  end

  describe "#seconds_remaining" do
    context "when time is left" do
      it "counts down to the expiry" do
        hold = build(:hold, expires_at: 90.seconds.from_now)
        expect(hold.seconds_remaining).to be_within(1).of(90)
      end
    end

    context "when the window has passed" do
      it "never goes negative" do
        expect(build(:hold, expires_at: 10.minutes.ago).seconds_remaining).to eq(0)
      end
    end
  end

  describe "scopes" do
    describe ".live" do
      it "includes an active hold inside its window" do
        hold = create(:hold, status: "active", expires_at: 2.minutes.from_now)
        expect(described_class.live).to include(hold)
      end

      it "excludes an active hold past its window" do
        hold = age_past_expiry(create(:hold, status: "active", expires_at: 2.minutes.from_now))
        expect(described_class.live).not_to include(hold)
      end

      it "excludes a converted hold" do
        hold = create(:hold, status: "converted", expires_at: 2.minutes.from_now)
        expect(described_class.live).not_to include(hold)
      end
    end

    describe ".expirable" do
      it "includes an active hold whose window has passed" do
        hold = age_past_expiry(create(:hold, status: "active", expires_at: 2.minutes.from_now))
        expect(described_class.expirable).to include(hold)
      end

      it "excludes a hold that is still live" do
        hold = create(:hold, status: "active", expires_at: 2.minutes.from_now)
        expect(described_class.expirable).not_to include(hold)
      end

      it "excludes a hold that was already released" do
        hold = age_past_expiry(create(:hold, status: "released", expires_at: 2.minutes.from_now))
        expect(described_class.expirable).not_to include(hold)
      end
    end
  end

  describe "database constraints" do
    it "refuses a hold that expires before it was created" do
      hold = create(:hold)

      expect { described_class.where(id: hold.id).update_all(expires_at: hold.created_at - 1.second) }
        .to raise_error(ActiveRecord::StatementInvalid, /holds_expire_after_creation/)
    end

    it "refuses an unknown status" do
      hold = create(:hold)

      expect { described_class.where(id: hold.id).update_all(status: "sideways") }
        .to raise_error(ActiveRecord::StatementInvalid, /holds_status_valid/)
    end
  end
end
