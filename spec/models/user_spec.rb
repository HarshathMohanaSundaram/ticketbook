require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:holds).dependent(:destroy) }
    it { is_expected.to have_many(:bookings).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }

    context "when the email is malformed" do
      it "is invalid" do
        expect(build(:user, email: "not-an-email")).not_to be_valid
      end
    end
  end

  describe "email handling" do
    context "when the same address differs only in case" do
      before { create(:user, email: "Ravi@Example.com") }

      it "is treated as one account by the citext column" do
        expect(described_class.find_by(email: "ravi@example.com")).to be_present
      end

      it "cannot be registered twice" do
        expect(build(:user, email: "RAVI@EXAMPLE.COM")).not_to be_valid
      end
    end

    context "when the address has stray whitespace" do
      it "is stored trimmed" do
        expect(create(:user, email: "  ravi@example.com  ").email).to eq("ravi@example.com")
      end
    end
  end

  describe "#display_name" do
    context "when a name is set" do
      it "returns the name" do
        expect(build(:user, name: "Ravi Kumar").display_name).to eq("Ravi Kumar")
      end
    end

    context "when no name is set" do
      it "falls back to the part before the at sign" do
        expect(build(:user, name: nil, email: "ravi@example.com").display_name).to eq("ravi")
      end
    end
  end

  describe "sign-in tokens" do
    let(:user) { create(:user) }

    it "verifies a fresh token" do
      expect(described_class.find_by_token_for(:sign_in, user.generate_token_for(:sign_in))).to eq(user)
    end

    it "rejects a tampered token" do
      token = user.generate_token_for(:sign_in).sub(/.$/, "x")
      expect(described_class.find_by_token_for(:sign_in, token)).to be_nil
    end

    it "rejects a token past its fifteen minute window" do
      token = user.generate_token_for(:sign_in)

      travel_to(described_class::SIGN_IN_TOKEN_WINDOW.from_now + 1.second) do
        expect(described_class.find_by_token_for(:sign_in, token)).to be_nil
      end
    end

    it "accepts a token just inside the window" do
      token = user.generate_token_for(:sign_in)

      travel_to(described_class::SIGN_IN_TOKEN_WINDOW.from_now - 5.seconds) do
        expect(described_class.find_by_token_for(:sign_in, token)).to eq(user)
      end
    end

    # updated_at is part of what the token signs, so signing in burns the link.
    it "rejects a token once the user has been touched" do
      token = user.generate_token_for(:sign_in)
      user.touch

      expect(described_class.find_by_token_for(:sign_in, token)).to be_nil
    end

    it "does not let one user's token sign in another" do
      other = create(:user)
      expect(described_class.find_by_token_for(:sign_in, other.generate_token_for(:sign_in))).not_to eq(user)
    end
  end
end
