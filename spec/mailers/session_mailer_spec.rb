require "rails_helper"

RSpec.describe SessionMailer, type: :mailer do
  describe "#magic_link" do
    subject(:mail) { described_class.with(user: user, token: token).magic_link }

    let(:user) { create(:user, name: "Ravi Kumar") }
    let(:token) { user.generate_token_for(:sign_in) }

    it "is addressed to the user" do
      expect(mail.to).to eq([ user.email ])
    end

    it "says what it is for" do
      expect(mail.subject).to eq("Your Ticketbook sign-in link")
    end

    it "greets the user by name" do
      expect(mail.body.encoded).to include("Ravi Kumar")
    end

    it "includes the sign-in link" do
      expect(mail.body.encoded).to include(token)
    end

    it "says how long the link lasts" do
      expect(mail.body.encoded).to include("15 minutes")
    end

    it "sends both a plain text and an HTML part" do
      expect(mail.body.parts.map(&:content_type).map { |type| type.split(";").first })
        .to contain_exactly("text/plain", "text/html")
    end

    context "when the user has no name" do
      let(:user) { create(:user, name: nil) }

      it "still renders" do
        expect(mail.body.encoded).to include("Hello")
      end
    end
  end
end
